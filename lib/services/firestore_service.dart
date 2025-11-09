import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';

/// Service for managing Firestore operations related to deliveries and drivers.
/// 
/// COMPANY CODE SYSTEM - PRIMARY USER LINKING METHODOLOGY
/// 
/// Company codes are the PRIMARY way to identify and link users:
/// 
/// ADMIN USERS (Web App Only):
///   - Company Admins: Work for big delivery companies (FedEx, DHL, UPS, Amazon)
///     * MUST have companyCode (required)
///     * Multiple admins can share the same companyCode
///   - Individual Admins: Freelancers looking for truck drivers
///     * MUST have companyCode (required)
///     * Each individual admin has their own unique companyCode
/// 
/// DRIVER USERS (Mobile App Only):
///   - Company Drivers: Have companyCode → linked to company via matching code
///     * Can only work with admins who have the same companyCode
///   - Freelance Drivers: No companyCode (null/empty) → can work with any admin
/// 
/// ORDER ASSIGNMENT LOGIC (for web app implementation):
/// - Company drivers (with companyCode): Only receive orders from admins
///   with the same companyCode
/// - Freelance drivers (no companyCode): Can receive orders from any admin
/// - All admins MUST have a companyCode (enforced during web app signup)
/// 
/// When assigning orders in the web app, filter available drivers based on:
/// 1. Admin has companyCode (required) → show only drivers with matching companyCode
/// 2. Also show freelance drivers (no companyCode) so admins can assign to them too
/// 3. Filter out drivers who are already assigned/in-progress (as needed)
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _deliveriesCollectionPath = 'deliveries';
  final String _usersCollectionPath = 'users';

  // Get deliveries assigned to a specific driver
  Stream<List<DeliveryAddress>> getDriverAssignedAddresses(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) {
              final data = doc.data();
              return DeliveryAddress.fromJson({
                'id': doc.id,
                ...data,
              });
            }).toList());
  }

  // Get completed deliveries for a specific driver
  Stream<List<DeliveryAddress>> getDriverCompletedAddresses(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) {
              final data = doc.data();
              return DeliveryAddress.fromJson({
                'id': doc.id,
                ...data,
              });
            }).toList());
  }

  // Get in-progress deliveries for a specific driver
  Stream<List<DeliveryAddress>> getDriverInProgressAddresses(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'in_progress')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) {
              final data = doc.data();
              return DeliveryAddress.fromJson({
                'id': doc.id,
                ...data,
              });
            }).toList());
  }

  // Update delivery status
  Future<void> updateAddressStatus(String addressId, String status) {
    return _db.collection(_deliveriesCollectionPath).doc(addressId).update({
      'status': status,
    });
  }

  // Get total count of deliveries for a driver
  Stream<int> getDriverAddressCount(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get count of completed deliveries for a driver
  Stream<int> getDriverCompletedCount(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get count of in-progress deliveries for a driver
  Stream<int> getDriverInProgressCount(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'in_progress')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Get available drivers for an admin based on company code linking rules.
  /// 
  /// Company Code Linking Rules:
  /// - Company drivers (with companyCode): Only visible to admins with matching companyCode
  /// - Freelance drivers (no companyCode): Visible to all admins
  /// 
  /// Args:
  ///   - adminCompanyCode: The company code of the admin (required)
  /// 
  /// Returns: Stream of user documents that represent available drivers
  Stream<List<Map<String, dynamic>>> getAvailableDriversForAdmin(String adminCompanyCode) {
    // Get all drivers
    // Note: Firestore doesn't support OR queries directly, so we need to:
    // 1. Get drivers with matching companyCode
    // 2. Get freelance drivers (no companyCode)
    // 3. Combine and filter client-side or use multiple queries
    
    return _db
        .collection(_usersCollectionPath)
        .where('userType', isEqualTo: 'driver')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .where((doc) {
            final data = doc.data();
            final driverCompanyCode = data['companyCode'] as String?;
            
            // Show drivers with matching companyCode OR freelance drivers (no code)
            return driverCompanyCode == null || 
                   driverCompanyCode.isEmpty || 
                   driverCompanyCode == adminCompanyCode;
          })
          .map((doc) => {
            'id': doc.id,
            ...doc.data(),
          })
          .toList();
    });
  }

  /// Get drivers linked to a specific company code.
  /// 
  /// Returns all drivers (both company and freelance) that can work with the given company code.
  Future<List<Map<String, dynamic>>> getDriversByCompanyCode(String companyCode) async {
    try {
      // Get company drivers with matching code
      final companyDrivers = await _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'driver')
          .where('companyCode', isEqualTo: companyCode)
          .get();

      // Get freelance drivers (no companyCode)
      final allDrivers = await _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'driver')
          .get();

      final freelanceDrivers = allDrivers.docs
          .where((doc) {
            final data = doc.data();
            final code = data['companyCode'] as String?;
            return code == null || code.isEmpty;
          })
          .toList();

      // Combine results
      final allAvailableDrivers = [
        ...companyDrivers.docs,
        ...freelanceDrivers,
      ];

      return allAvailableDrivers.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      print('Error getting drivers by company code: $e');
      return [];
    }
  }

  /// Get admins that a driver can communicate/work with based on company code.
  /// 
  /// Rules:
  /// - Company drivers (with companyCode): Can only see admins with matching companyCode
  /// - Freelance drivers (no companyCode): Can see all admins
  /// 
  /// Args:
  ///   - driverCompanyCode: The company code of the driver (null/empty for freelancers)
  /// 
  /// Returns: Stream of admin user documents
  Stream<List<Map<String, dynamic>>> getAvailableAdminsForDriver(String? driverCompanyCode) {
    if (driverCompanyCode == null || driverCompanyCode.isEmpty) {
      // Freelance drivers can see all admins
      return _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'admin')
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
              .toList());
    } else {
      // Company drivers can only see admins with matching companyCode
      return _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'admin')
          .where('companyCode', isEqualTo: driverCompanyCode)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
              .toList());
    }
  }

  /// Check if a driver and admin can work together based on company codes.
  /// 
  /// Returns true if:
  /// - Driver is freelance (no companyCode) → can work with any admin
  /// - Driver has companyCode matching admin's companyCode
  bool canDriverWorkWithAdmin(String? driverCompanyCode, String adminCompanyCode) {
    if (driverCompanyCode == null || driverCompanyCode.isEmpty) {
      // Freelance driver can work with any admin
      return true;
    }
    // Company driver can only work with matching company admin
    return driverCompanyCode == adminCompanyCode;
  }
}
