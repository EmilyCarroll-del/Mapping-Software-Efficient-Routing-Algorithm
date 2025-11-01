// lib/services/notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // to avoid attaching the same listeners twice (driver + admin in same tab)
  bool _listenersAttached = false;

  /// DRIVER side
  /// call right after driver signs in / opens driver map screen
  Future<void> initForDriver(String driverId) async {
    await _initCommon(userId: driverId, role: 'driver');
  }

  /// ADMIN side
  /// call right after admin logs in / opens dashboard
  Future<void> initForAdmin(String adminId) async {
    await _initCommon(userId: adminId, role: 'admin');
  }

  /// shared logic for any role
  Future<void> _initCommon({
    required String userId,
    required String role,
  }) async {
    // 1. ask for permission
    await _requestPermission();

    // 2. get FCM token (web needs vapidKey)
    final token = await _messaging.getToken(
      vapidKey: "BAEXeAwTaHrsEDu5-we5yu9YAnnOaEvKqF8s_dM_J2WJbp-9T2YoL54DRa2T61LBSjbHgBSNU3Xh2KmPvoS1ILs",
    );

    if (token == null) {
      debugPrint("❌ could not get FCM token for $role");
      return;
    }

    debugPrint("✅ $role FCM token: $token");

    // 3. save in Firestore so Cloud Function can find it
    await _saveTokenToFirestore(
      userId: userId,
      role: role,
      token: token,
    );

    // 4. attach listeners (but only once)
    if (!_listenersAttached) {
      _attachForegroundListeners();
      _listenersAttached = true;
    }
  }

  void _attachForegroundListeners() {
    // when app is OPEN
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      final type = data['type'];

      if (type == 'ADMIN_MESSAGE') {
        final from = data['from'] ?? 'Admin';
        final body = data['body'] ?? '';
        debugPrint("📩 message from $from: $body");
        // later: show snackbar / refresh inbox
      } else {
        debugPrint("📩 foreground message (no type): ${message.data}");
      }
    });

    // when user CLICKS notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final data = message.data;
      if (data['type'] == 'ADMIN_MESSAGE') {
        // TODO: navigate to InboxPage
        debugPrint("➡️ user opened ADMIN_MESSAGE notification");
      }
    });
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint("🟢 notification permission: ${settings.authorizationStatus}");
  }

  Future<void> _saveTokenToFirestore({
    required String userId,
    required String role,
    required String token,
  }) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .set({
      'role': role,
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint("✅ FCM token saved in Firestore for $userId ($role)");
  }
}
