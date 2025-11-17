// lib/services/notification_service.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NotificationService {
  // navigatorKey is OPTIONAL so existing NotificationService() calls still work.
  NotificationService([this.navigatorKey]);

  // Used to navigate when a push notification is tapped.
  // May be null if caller doesn't care about routing.
  final GlobalKey<NavigatorState>? navigatorKey;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  StreamSubscription<QuerySnapshot>? _orderListener;

  bool _isInitialized = false;
  String? _currentUserId;

  /// Tracks the last seen state for each order so we only notify on changes
  /// (key: orderId, value: {'status': String, 'address': String})
  final Map<String, Map<String, dynamic>> _lastOrderStates = {};

  /// Initialize push + Firestore listeners (Spark-friendly: all client-side)
  Future<void> initialize() async {
    if (_isInitialized) return;

    final user = _auth.currentUser;
    if (user == null) return;

    _currentUserId = user.uid;

    try {
      // -----------------------------
      // 1) Ask permission + save FCM token
      // -----------------------------
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await _messaging.getToken();
        if (token != null) {
          await _saveFCMToken(user.uid, token);
        }

        _messaging.onTokenRefresh.listen((newToken) {
          _saveFCMToken(user.uid, newToken);
        });
      } else {
        debugPrint('🔕 Notifications permission not granted');
      }

      // -----------------------------
      // 2) FCM listeners
      // -----------------------------
      // Foreground: just log for now (Android system tray handles bg)
      FirebaseMessaging.onMessage.listen((msg) {
        debugPrint('📩 onMessage (foreground): ${msg.data}');
      });

      // When app is opened from a notification tap (background -> foreground)
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        debugPrint('➡️ onMessageOpenedApp: ${msg.data}');
        _handleNotificationTap(msg);
      });

      // When app is launched from a terminated state via a notification tap.
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(
            '🚀 App launched from terminated via notification: ${initialMessage.data}');
        _handleNotificationTap(initialMessage);
      }

      // -----------------------------
      // 3) Orders listener (driver-only)
      // -----------------------------
      await _setupOrderListeners();

      _isInitialized = true;
    } catch (e) {
      debugPrint('❌ Error initializing NotificationService: $e');
    }
  }

  Future<void> dispose() async {
    await _orderListener?.cancel();
    _lastOrderStates.clear();
    _isInitialized = false;
    _currentUserId = null;
  }

  Future<void> _saveFCMToken(String userId, String token) async {
    try {
      await _db.collection('users').doc(userId).set(
        {
          'fcmToken': token,
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  /// Listen to the current driver's assigned orders and create notifications
  /// only when a new assignment appears or the status changes.
  Future<void> _setupOrderListeners() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _orderListener?.cancel();

    bool seeded = false;

    _orderListener = _db
        .collection('addresses')
        .where('driverId', isEqualTo: user.uid)
        .snapshots()
        .listen((snapshot) async {
      // First pass: seed the state without creating notifications
      if (!seeded) {
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          _lastOrderStates[doc.id] = {
            'status': (data['status'] ?? 'assigned') as String,
            'address': _formatAddress(data),
          };
        }
        seeded = true;
        return;
      }

      // Track current doc IDs for cleanup
      final liveIds = snapshot.docs.map((d) => d.id).toSet();

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.isEmpty) continue;

        final orderId = doc.id;
        final currentStatus = (data['status'] ?? 'assigned') as String;
        final address = _formatAddress(data);

        final prev = _lastOrderStates[orderId];

        if (prev == null) {
          // New assignment detected
          await _createOrderNotification(
            orderId: orderId,
            address: address,
            newStatus: currentStatus,
            type: _OrderEvent.newAssignment,
          );
        } else if (prev['status'] != currentStatus) {
          // Status changed
          await _createOrderNotification(
            orderId: orderId,
            address: address,
            oldStatus: prev['status'] as String,
            newStatus: currentStatus,
            type: _OrderEvent.statusChange,
          );
        }

        // Update cache
        _lastOrderStates[orderId] = {
          'status': currentStatus,
          'address': address,
        };
      }

      // Remove any orders that no longer appear in the stream
      _lastOrderStates.removeWhere((id, _) => !liveIds.contains(id));
    });
  }

  /// Creates a single, de-duplicated order notification by writing to a
  /// deterministic document ID. If the same (user, orderId, status) shows up
  /// again, it won’t create extra rows/cards.
  Future<void> _createOrderNotification({
    required String orderId,
    required String address,
    String? oldStatus,
    String? newStatus,
    required _OrderEvent type,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final currentStatus = newStatus ?? 'assigned';

    late final String title;
    late final String body;

    if (type == _OrderEvent.newAssignment) {
      title = 'New Order Assigned';
      body = 'You have been assigned a new order: $address';
    } else if (type == _OrderEvent.statusChange) {
      title = 'Order Status Updated';
      body =
      'Order status changed from ${_formatStatus(oldStatus)} to ${_formatStatus(newStatus)}: $address';
    } else {
      title = 'Order Update';
      body = 'Order update: $address';
    }

    // Deterministic doc id = order_<userId>_<orderId>_<status>
    final id = 'order_${user.uid}_${orderId}_${currentStatus}';

    await _createNotificationWithId(
      id: id,
      userId: user.uid,
      type: 'order',
      title: title,
      message: body,
      actionType: 'view_order',
      actionData: {'orderId': orderId},
      metadata: {
        'orderStatus': currentStatus,
        'address': address,
      },
    );
  }

  /// Generic helper when you want to force a stable ID (prevents duplicates).
  Future<void> _createNotificationWithId({
    required String id,
    required String userId,
    required String type,
    required String title,
    required String message,
    String actionType = 'none',
    Map<String, dynamic>? actionData,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _db.collection('notifications').doc(id).set({
        'userId': userId,
        'type': type, // 'order' | 'message' | 'system' | 'news'
        'title': title,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'actionType': actionType, // 'view_order' | 'open_chat' | 'none'
        'actionData': actionData ?? <String, dynamic>{},
        'metadata': metadata ?? <String, dynamic>{},
      }, SetOptions(merge: false)); // overwrite if same id shows up again
    } catch (e) {
      debugPrint('❌ Error creating notification (with id): $e');
    }
  }

  /// Generic helper when de-duplication is not required.
  /// TIP: for chat, pass metadata: {'senderName': '<display name>', 'senderId': '<uid>'}
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String message,
    String actionType = 'none',
    Map<String, dynamic>? actionData,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _db.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'actionType': actionType,
        'actionData': actionData ?? <String, dynamic>{},
        'metadata': metadata ?? <String, dynamic>{},
      });
    } catch (e) {
      debugPrint('❌ Error creating notification: $e');
    }
  }

  Future<void> markAsRead(String notificationId) async {
    try {
      await _db.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      debugPrint('❌ Error marking notification as read: $e');
    }
  }

  Future<void> markAllAsRead() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final q = await _db
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (final doc in q.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ Error marking all as read: $e');
    }
  }

  Stream<int> getUnreadCount() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<int>.value(0);
    }
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((s) => s.docs.length);
  }

  Stream<QuerySnapshot> getNotifications() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // ---- FCM tap handler / navigation ----

  void _handleNotificationTap(RemoteMessage message) {
    // If no navigatorKey was provided (e.g., some other caller used
    // NotificationService() without args), just log and bail out.
    if (navigatorKey == null) {
      debugPrint(
          '🔔 Notification tap received but navigatorKey is null; skipping navigation.');
      return;
    }

    final ctx = navigatorKey!.currentContext;
    if (ctx == null) {
      debugPrint('⚠️ No navigator context available for navigation');
      return;
    }

    final data = message.data;
    final type = data['type'] as String?; // e.g., "chat", "assigned_orders", etc.

    debugPrint('🔔 Handling notification tap with type=$type data=$data');

    if (type == 'chat') {
      // Expecting data payload like:
      // {
      //   "type": "chat",
      //   "conversationId": "...",
      //   "otherUserId": "...",
      //   "otherUserName": "Alice",
      //   "orderId": "...",        // optional
      //   "orderTitle": "...",     // optional
      //   "isOldFormat": "false"   // or "true"
      // }
      final extras = <String, dynamic>{
        'conversationId': data['conversationId']?.toString(),
        'otherUserId': data['otherUserId']?.toString(),
        'otherUserName':
        (data['otherUserName']?.toString().isNotEmpty ?? false)
            ? data['otherUserName'].toString()
            : 'User',
        'orderId': data['orderId']?.toString(),
        'orderTitle': data['orderTitle']?.toString(),
        'isOldFormat': _parseBool(data['isOldFormat']),
      };

      ctx.go('/chat', extra: extras);
    } else if (type == 'assigned_orders' || type == 'order') {
      // "order" type also routed to the assigned orders screen
      ctx.go('/assigned-orders');
    } else if (type == 'inbox') {
      ctx.go('/inbox');
    } else {
      // Fallback: app notifications screen
      ctx.go('/notifications');
    }
  }

  bool _parseBool(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    if (value is num) return value != 0;
    return false;
  }

  // ---- helpers ----

  String _formatAddress(Map<String, dynamic> data) {
    final street = (data['streetAddress'] ?? '').toString();
    final city = (data['city'] ?? '').toString();
    final state = (data['state'] ?? '').toString();
    final zip = (data['zipCode'] ?? '').toString();
    return '$street, $city, $state $zip'.trim();
  }

  String _formatStatus(String? status) {
    if (status == null) return 'UNKNOWN';
    return status.replaceAll('_', ' ').toUpperCase();
  }
}

enum _OrderEvent { newAssignment, statusChange }
