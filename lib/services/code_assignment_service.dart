import 'package:cloud_firestore/cloud_firestore.dart';
import 'company_service.dart';

/// Service for managing code assignments and regeneration.
/// 
/// Tracks which codes are assigned to which drivers and handles automatic
/// code regeneration when drivers claim codes.
class CodeAssignmentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _assignmentsCollectionPath = 'code_assignments';
  final CompanyService _companyService = CompanyService();

  /// Get code assignment details.
  Future<Map<String, dynamic>?> getCodeAssignment(String code) async {
    try {
      final doc = await _db.collection(_assignmentsCollectionPath).doc(code).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('Error getting code assignment: $e');
      return null;
    }
  }

  /// Claim a code for a driver and regenerate code for admin.
  /// 
  /// When a driver saves a code in their profile:
  /// 1. Check if driver already has any claimed codes
  /// 2. Revoke all old codes (one-driver-one-code constraint)
  /// 3. Mark the code as claimed by this driver
  /// 4. Auto-regenerate a new code for the admin
  /// Returns the new code string, or null if code wasn't in assignments
  Future<String?> claimCode({
    required String code,
    required String driverId,
  }) async {
    try {
      final assignment = await getCodeAssignment(code);
      
      if (assignment == null) {
        // Code not in assignments - might be manually entered, allow it
        return null;
      }

      if (assignment['status'] == 'claimed') {
        // Check if this driver already owns this code
        if (assignment['driverId'] == driverId) {
          // Driver already owns this code, nothing to do
          return null;
        }
        // Code already claimed by another driver
        throw Exception('This code has already been claimed by another driver');
      }

      if (assignment['status'] != 'available') {
        throw Exception('Code is not available for claiming');
      }

      // Enforce one-driver-one-code constraint: revoke all old codes first
      await revokeAllDriverCodes(driverId);

      final adminId = assignment['adminId'] as String;
      final companyId = assignment['companyId'] as String;

      // Mark code as claimed
      await _db.collection(_assignmentsCollectionPath).doc(code).update({
        'driverId': driverId,
        'status': 'claimed',
        'claimedAt': FieldValue.serverTimestamp(),
      });

      // Auto-regenerate new code for the admin
      final newCode = await regenerateAdminCode(
        adminId: adminId,
        companyId: companyId,
      );

      // Update admin's profile with new code
      if (newCode != null) {
        await _db.collection('users').doc('${adminId}_admin').update({
          'companyCode': newCode.toString(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return newCode?.toString();
    } catch (e) {
      print('Error claiming code: $e');
      rethrow;
    }
  }

  /// Regenerate a code for an admin.
  /// 
  /// Generates a new code within the company's range and creates
  /// a new assignment document.
  Future<int?> regenerateAdminCode({
    required String adminId,
    required String companyId,
  }) async {
    try {
      // Generate new code within company range
      final newCode = await _companyService.generateCodeForCompanyAsync(companyId);
      
      if (newCode == null) {
        print('Failed to generate new code for company: $companyId');
        return null;
      }

      // Check if code already exists (unlikely but possible)
      var attempts = 0;
      int? codeToUse = newCode;
      while (codeToUse != null && await getCodeAssignment(codeToUse.toString()) != null && attempts < 5) {
        codeToUse = await _companyService.generateCodeForCompanyAsync(companyId);
        attempts++;
      }

      if (codeToUse == null) {
        return null;
      }

      // Create new assignment for the regenerated code
      await _db.collection(_assignmentsCollectionPath).doc(codeToUse.toString()).set({
        'code': codeToUse.toString(),
        'adminId': adminId,
        'companyId': companyId,
        'driverId': null,
        'status': 'available',
        'createdAt': FieldValue.serverTimestamp(),
        'claimedAt': null,
      }, SetOptions(merge: true));

      return codeToUse;
    } catch (e) {
      print('Error regenerating admin code: $e');
      return null;
    }
  }

  /// Check if a code is available for claiming.
  Future<bool> isCodeAvailable(String code) async {
    try {
      final assignment = await getCodeAssignment(code);
      if (assignment == null) return false;
      return assignment['status'] == 'available';
    } catch (e) {
      print('Error checking code availability: $e');
      return false;
    }
  }

  /// Get all codes claimed by a specific driver.
  /// 
  /// Returns a list of claimed code assignments for the given driver.
  Future<List<Map<String, dynamic>>> getDriverClaimedCodes(String driverId) async {
    try {
      final snapshot = await _db
          .collection(_assignmentsCollectionPath)
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'claimed')
          .get();

      if (snapshot.docs.isEmpty) {
        return [];
      }

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'code': data['code'],
          'adminId': data['adminId'],
          'companyId': data['companyId'],
          'claimedAt': data['claimedAt'],
          ...data,
        };
      }).toList();
    } catch (e) {
      print('Error getting driver claimed codes: $e');
      return [];
    }
  }

  /// Revoke a specific code assignment.
  /// 
  /// Marks the code as available again and removes the driver association.
  Future<void> revokeCode({required String code}) async {
    try {
      await _db.collection(_assignmentsCollectionPath).doc(code).update({
        'driverId': null,
        'status': 'available',
        'claimedAt': null,
        'revokedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error revoking code: $e');
      rethrow;
    }
  }

  /// Revoke all codes claimed by a specific driver.
  /// 
  /// This ensures one-driver-one-code constraint when a driver claims a new code.
  Future<void> revokeAllDriverCodes(String driverId) async {
    try {
      final claimedCodes = await getDriverClaimedCodes(driverId);
      
      if (claimedCodes.isEmpty) {
        return;
      }

      // Revoke all codes in parallel
      final batch = _db.batch();
      for (final codeData in claimedCodes) {
        final code = codeData['code'] as String;
        final codeRef = _db.collection(_assignmentsCollectionPath).doc(code);
        batch.update(codeRef, {
          'driverId': null,
          'status': 'available',
          'claimedAt': null,
          'revokedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
    } catch (e) {
      print('Error revoking all driver codes: $e');
      rethrow;
    }
  }

  /// Get current available code for an admin.
  /// 
  /// Returns the code string, or null if admin has no available codes.
  Future<String?> getAdminCurrentCode(String adminId) async {
    try {
      final snapshot = await _db
          .collection(_assignmentsCollectionPath)
          .where('adminId', isEqualTo: adminId)
          .where('status', isEqualTo: 'available')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return snapshot.docs.first.data()['code'] as String?;
    } catch (e) {
      print('Error getting admin current code: $e');
      return null;
    }
  }

  /// Get all code assignments for an admin.
  /// 
  /// Returns all codes (both available and claimed) for the given admin.
  Future<List<Map<String, dynamic>>> getAdminCodes(String adminId) async {
    try {
      final snapshot = await _db
          .collection(_assignmentsCollectionPath)
          .where('adminId', isEqualTo: adminId)
          .get();

      if (snapshot.docs.isEmpty) {
        return [];
      }

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'code': data['code'],
          'adminId': data['adminId'],
          'companyId': data['companyId'],
          'driverId': data['driverId'],
          'status': data['status'],
          'createdAt': data['createdAt'],
          'claimedAt': data['claimedAt'],
        };
      }).toList();
    } catch (e) {
      print('Error getting admin codes: $e');
      return [];
    }
  }

  /// Generate a new code for an admin without requiring a claim.
  /// 
  /// Allows admins to generate multiple codes manually.
  /// Returns the generated code, or null if generation failed.
  Future<String?> generateNewCodeForAdmin({
    required String adminId,
    required String companyId,
  }) async {
    try {
      final newCode = await regenerateAdminCode(
        adminId: adminId,
        companyId: companyId,
      );

      return newCode?.toString();
    } catch (e) {
      print('Error generating new code for admin: $e');
      return null;
    }
  }

  /// Get all drivers who have claimed any of the admin's codes.
  /// 
  /// Returns a list of driver information including their codes.
  Future<List<Map<String, dynamic>>> getAdminDrivers(String adminId) async {
    try {
      // Get all claimed codes for this admin (without orderBy to avoid index requirement)
      final snapshot = await _db
          .collection(_assignmentsCollectionPath)
          .where('adminId', isEqualTo: adminId)
          .where('status', isEqualTo: 'claimed')
          .get();

      if (snapshot.docs.isEmpty) {
        return [];
      }

      // Fetch driver profiles for each claimed code
      final List<Map<String, dynamic>> drivers = [];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final driverId = data['driverId'] as String?;
        
        if (driverId != null) {
          try {
            // Fetch driver profile
            final driverDoc = await _db.collection('users').doc('${driverId}_driver').get();
            if (driverDoc.exists) {
              final driverData = driverDoc.data()!;
              drivers.add({
                'driverId': driverId,
                'code': data['code'],
                'claimedAt': data['claimedAt'],
                'name': driverData['name'] ?? driverData['first_name'] ?? 'Unknown',
                'email': driverData['email'] ?? '',
                'phone': driverData['phone'] ?? '',
                'profileImageUrl': driverData['profileImageUrl'],
              });
            }
          } catch (e) {
            print('Error fetching driver profile for $driverId: $e');
          }
        }
      }

      // Sort by claimedAt timestamp in descending order (most recent first)
      drivers.sort((a, b) {
        final aTime = a['claimedAt'] as Timestamp?;
        final bTime = b['claimedAt'] as Timestamp?;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime); // Descending order
      });

      return drivers;
    } catch (e) {
      print('Error getting admin drivers: $e');
      return [];
    }
  }
}

