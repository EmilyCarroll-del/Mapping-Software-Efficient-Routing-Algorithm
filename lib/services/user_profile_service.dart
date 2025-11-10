// lib/services/user_profile_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class UserProfileService {
  // ---- IMPORTANT: paste your Web Push (VAPID) key here ----
  // From Firebase Console -> Project Settings -> Cloud Messaging -> Web configuration -> Key pair
  static const String webVapidKey =
      "BAEXeAwTaHrsEDu5-we5yu9YAnnOaEvKqF8s_dM_J2WJbp-9T2YoL54DRa2T61LBSjbHgBSNU3Xk2KmPvoS1ILs";

  /// Call this right after a successful sign-in (email or Google).
  /// - Creates/merges full profile shape in /users/{uid}
  /// - Requests notification permission
  /// - Saves/refreshes FCM token (web+mobile)
  /// - Updates lastSignIn and updatedAt
  static Future<void> updateOnSignIn(
      BuildContext context, {
        required String inferredRole,
      }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final usersCol = FirebaseFirestore.instance.collection('users');
    final userRef = usersCol.doc(user.uid);
    final snap = await userRef.get();
    final existing = snap.data() ?? <String, dynamic>{};

    // Derive name pieces from displayName if missing
    final displayName = (user.displayName ?? '').trim();
    String derivedFirst = existing['firstName'] ?? '';
    String derivedLast = existing['lastName'] ?? '';

    if ((derivedFirst.isEmpty || derivedLast.isEmpty) && displayName.isNotEmpty) {
      final parts = displayName.split(RegExp(r'\s+'));
      if (derivedFirst.isEmpty) derivedFirst = parts.isNotEmpty ? parts.first : '';
      if (derivedLast.isEmpty) derivedLast = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    final now = Timestamp.now();

    // Only set role if doc has no role; don't overwrite an assigned role.
    final String roleToSave = (existing['role'] is String && (existing['role'] as String).isNotEmpty)
        ? existing['role'] as String
        : inferredRole;

    // Provider best-guess
    final provider = user.providerData.isNotEmpty
        ? user.providerData.first.providerId
        : 'password';

    // Prepare a profile upsert (don’t wipe existing non-empty values)
    final Map<String, dynamic> profilePatch = {
      'email': existing['email'] ?? (user.email ?? ''),
      'name': existing['name'] ?? (displayName.isNotEmpty ? displayName : ''),
      'firstName': existing['firstName'] ?? derivedFirst,
      'lastName': existing['lastName'] ?? derivedLast,
      'bio': existing['bio'] ?? '',
      'phone': existing['phone'] ?? '',
      'profileImageUrl': existing['profileImageUrl'] ?? (user.photoURL ?? ''),
      'company': existing['company'] ?? 'GraphGo ',
      'companyCode': existing['companyCode'] ?? '79977',
      'provider': existing['provider'] ?? provider,
      'role': roleToSave,
      'createdAt': existing['createdAt'] ?? now,
      'updatedAt': now,
      'lastSignIn': now,
    };

    // Save base profile (merge)
    await userRef.set(profilePatch, SetOptions(merge: true));

    // ---- Push permission + token ----
    String? token;
    try {
      final messaging = FirebaseMessaging.instance;

      // Ask for permission on both platforms (web shows browser prompt)
      await messaging.requestPermission();

      if (kIsWeb) {
        token = await messaging.getToken(vapidKey: webVapidKey);
      } else {
        token = await messaging.getToken();
      }
    } catch (e) {
      // If permission denied or something failed, just continue without token.
      debugPrint('FCM token fetch failed: $e');
    }

    if (token != null && token.isNotEmpty) {
      await userRef.set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': now,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    }
  }
}
