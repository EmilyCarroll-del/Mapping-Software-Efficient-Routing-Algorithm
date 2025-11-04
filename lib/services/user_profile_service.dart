import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class UserProfileService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Call this after a successful sign-in.
  static Future<void> upsertCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Try getting FCM token (works on web/Android)
    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {}

    final now = FieldValue.serverTimestamp();
    final docRef = _db.collection('users').doc(user.uid);
    final docSnap = await docRef.get();

    final base = <String, dynamic>{
      'email': user.email ?? '',
      'name': user.displayName ?? '',
      'firstName': '',
      'lastName': '',
      'bio': '',
      'phone': '',
      'profileImageUrl': user.photoURL ?? '',
      'provider': user.providerData.isNotEmpty ? user.providerData.first.providerId : 'password',
      'company': 'GraphGo ',
      'companyCode': '',
      'role': 'Driver', // or 'Admin' if your UI sets it
      'createdAt': now,
      'updatedAt': now,
      'lastSignIn': now,
    };

    if (!docSnap.exists) {
      await docRef.set({
        ...base,
        if (token != null && token.isNotEmpty) 'fcmToken': token,
        'fcmTokenUpdatedAt': now,
      }, SetOptions(merge: true));
    } else {
      await docRef.set({
        'updatedAt': now,
        'lastSignIn': now,
        if (token != null && token.isNotEmpty) 'fcmToken': token,
        if (token != null && token.isNotEmpty) 'fcmTokenUpdatedAt': now,
      }, SetOptions(merge: true));
    }
  }
}
