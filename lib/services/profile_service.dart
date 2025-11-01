import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for managing separate admin and driver profiles for the same email/UID.
/// 
/// Allows users with the same email to have completely separate profiles:
/// - Admin profile: `users/{uid}_admin`
/// - Driver profile: `users/{uid}_driver`
class ProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _usersCollectionPath = 'users';

  /// Get the document path for a user profile based on userType.
  /// 
  /// Returns document ID in format: `{uid}_admin` or `{uid}_driver`
  String getProfileDocId(String uid, String userType) {
    if (userType == 'admin' || userType == 'Admin') {
      return '${uid}_admin';
    } else if (userType == 'driver' || userType == 'Driver') {
      return '${uid}_driver';
    }
    // Fallback to uid if userType is unknown
    return uid;
  }

  /// Get a reference to the user profile document based on userType.
  DocumentReference getProfileDocRef(String uid, String userType) {
    final docId = getProfileDocId(uid, userType);
    return _db.collection(_usersCollectionPath).doc(docId);
  }

  /// Fetch user profile data for a specific role.
  Future<Map<String, dynamic>?> getProfile(String uid, String userType) async {
    try {
      final docRef = getProfileDocRef(uid, userType);
      final doc = await docRef.get();
      
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      print('Error getting profile: $e');
      return null;
    }
  }

  /// Stream user profile data for a specific role.
  Stream<DocumentSnapshot> getProfileStream(String uid, String userType) {
    final docRef = getProfileDocRef(uid, userType);
    return docRef.snapshots();
  }

  /// Update or create user profile for a specific role.
  Future<void> updateProfile(String uid, String userType, Map<String, dynamic> data) async {
    try {
      final docRef = getProfileDocRef(uid, userType);
      
      // Always include userType and uid in the document
      final profileData = {
        ...data,
        'uid': uid,
        'userType': userType.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      await docRef.set(profileData, SetOptions(merge: true));
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    }
  }

  /// Create initial profile document for a specific role.
  Future<void> createProfile(String uid, String userType, Map<String, dynamic> initialData) async {
    try {
      final docRef = getProfileDocRef(uid, userType);
      
      final profileData = {
        ...initialData,
        'uid': uid,
        'userType': userType.toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      await docRef.set(profileData);
    } catch (e) {
      print('Error creating profile: $e');
      rethrow;
    }
  }

  /// Check if a profile exists for a specific role.
  Future<bool> profileExists(String uid, String userType) async {
    try {
      final docRef = getProfileDocRef(uid, userType);
      final doc = await docRef.get();
      return doc.exists;
    } catch (e) {
      print('Error checking profile existence: $e');
      return false;
    }
  }
}

