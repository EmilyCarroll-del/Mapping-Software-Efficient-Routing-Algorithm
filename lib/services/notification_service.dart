// lib/services/notification_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Web (admin) helper for FCM token management (optional) and
/// creating exactly ONE Firestore notification per message sent.
/// Mobile reads these docs to render the in-app card and deep-link.
///
/// IMPORTANT:
/// - Only the SENDER should call createChatNotificationForRecipient.
/// - We use a deterministic document id to prevent duplicates.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _listenersAttached = false;

  Future<void> initForDriver(String driverId) async {
    await _initCommon(userId: driverId, role: 'driver');
  }

  Future<void> initForAdmin(String adminId) async {
    await _initCommon(userId: adminId, role: 'admin');
  }

  Future<void> _initCommon({
    required String userId,
    required String role,
  }) async {
    await _requestPermission();

    final token = await _messaging.getToken(
      // Your Web push key (ok to be public in client apps)
      vapidKey:
      "BAEXeAwTaHrsEDu5-we5yu9YAnnOaEvKqF8s_dM_J2WJbp-9T2YoL54DRa2T61LBSjbHgBSNU3Xh2KmPvoS1ILs",
    );

    if (token == null) {
      debugPrint("❌ could not get FCM token for $role");
      return;
    }

    debugPrint("✅ $role FCM token: $token");

    await _saveTokenToFirestore(
      userId: userId,
      role: role,
      token: token,
    );

    if (!_listenersAttached) {
      _attachForegroundListeners();
      _listenersAttached = true;
    }
  }

  void _attachForegroundListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final data = message.data;
      final type = data['type'];
      if (type == 'ADMIN_MESSAGE') {
        final from = data['from'] ?? 'Admin';
        final body = data['body'] ?? '';
        debugPrint("📩 message from $from: $body");
      } else {
        debugPrint("📩 foreground message (no type): ${message.data}");
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final data = message.data;
      if (data['type'] == 'ADMIN_MESSAGE') {
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
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'role': role,
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint("✅ FCM token saved in Firestore for $userId ($role)");
  }

  // ---------------------------------------------------------------------------
  // Create an in-app notification doc for the RECIPIENT after writing a message
  // ---------------------------------------------------------------------------
  Future<void> createChatNotificationForRecipient({
    required String recipientUserId,   // driver (or other admin)
    required String conversationId,    // chat id
    required String senderUserId,      // current admin uid
    required String senderName,        // display name shown in title
    required String messageId,         // message doc id just created
    required String messageText,       // text (or caption)
    String messageType = 'text',       // 'text' | 'image'
    bool isOldFormat = false,          // true for 'chats' collection
  }) async {
    try {
      // Build a clean preview
      String preview;
      if (messageType == 'image') {
        preview = '📷 Photo';
      } else {
        final trimmed = messageText.trim();
        if (trimmed.isEmpty) {
          preview = 'New message';
        } else {
          preview = trimmed.length > 120 ? '${trimmed.substring(0, 120)}…' : trimmed;
        }
      }

      // Deterministic doc id prevents duplicates if called twice
      final docId = 'msg_${messageId}_$recipientUserId';

      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(docId)
          .set({
        'userId': recipientUserId,
        'type': 'message',
        'title': 'New message from $senderName',
        'message': preview,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,

        'actionType': 'open_chat',
        'actionData': {
          'conversationId': conversationId,
          'otherUserId': senderUserId,
          'isOldFormat': isOldFormat, // mobile reads this to route to /chats
        },

        'metadata': {
          'senderName': senderName,
          'senderId': senderUserId,
          'messageId': messageId,
          'messageType': messageType,
        },
      }, SetOptions(merge: false));

      debugPrint('🔔 notification $docId → '
          'recipient=$recipientUserId convo=$conversationId old=$isOldFormat');
    } catch (e) {
      debugPrint('❌ failed to create chat notification: $e');
      rethrow;
    }
  }
}