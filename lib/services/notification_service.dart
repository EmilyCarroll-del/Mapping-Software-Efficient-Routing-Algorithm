import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'chat_service.dart';

class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final ChatService _chatService = ChatService();

  StreamSubscription<QuerySnapshot>? _orderListener;
  Map<String, StreamSubscription<QuerySnapshot>> _messageListeners = {};
  bool _isInitialized = false;
  String? _currentUserId;
  Map<String, Map<String, dynamic>> _lastOrderStates = {};

  // Initialize FCM and setup listeners
  Future<void> initialize() async {
    if (_isInitialized) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _currentUserId = currentUser.uid;

    try {
      // Request notification permissions
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // Get FCM token
        final token = await _messaging.getToken();
        if (token != null) {
          await _saveFCMToken(currentUser.uid, token);
        }

        // Listen for token refresh
        _messaging.onTokenRefresh.listen((newToken) {
          _saveFCMToken(currentUser.uid, newToken);
        });

        // Setup foreground message handler
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Setup background message handler (static)
        FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

        // Check for initial notification (app opened from terminated state)
        final initialMessage = await _messaging.getInitialMessage();
        if (initialMessage != null) {
          _handleBackgroundMessage(initialMessage);
        }
      }

      // Setup order and message listeners
      await _setupOrderListeners();
      await _setupMessageListeners();

      _isInitialized = true;
    } catch (e) {
      print('Error initializing NotificationService: $e');
    }
  }

  // Save FCM token to user document
  Future<void> _saveFCMToken(String userId, String token) async {
    try {
      await _db.collection('users').doc(userId).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  // Handle foreground messages (app is open)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Received foreground message: ${message.messageId}');

    // Create notification in Firestore
    await createNotification(
      userId: _currentUserId ?? '',
      type: message.data['type'] ?? 'system',
      title: message.notification?.title ?? message.data['title'] ?? 'Notification',
      message: message.notification?.body ?? message.data['message'] ?? '',
      actionType: message.data['actionType'] ?? 'none',
      actionData: {
        'orderId': message.data['orderId'],
        'conversationId': message.data['conversationId'],
        'url': message.data['url'],
      },
    );
  }

  // Handle background messages (app in background or terminated)
  Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    print('Received background message: ${message.messageId}');

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Create notification in Firestore
    await createNotification(
      userId: currentUser.uid,
      type: message.data['type'] ?? 'system',
      title: message.notification?.title ?? message.data['title'] ?? 'Notification',
      message: message.notification?.body ?? message.data['message'] ?? '',
      actionType: message.data['actionType'] ?? 'none',
      actionData: {
        'orderId': message.data['orderId'],
        'conversationId': message.data['conversationId'],
        'url': message.data['url'],
      },
    );
  }

  // Setup listeners for order changes
  Future<void> _setupOrderListeners() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _orderListener?.cancel();

    // Listen to addresses assigned to current driver
    final isFirstLoad = _lastOrderStates.isEmpty;
    
    _orderListener = _db
        .collection('addresses')
        .where('driverId', isEqualTo: currentUser.uid)
        .snapshots()
        .listen((snapshot) async {
      if (isFirstLoad) {
        // First load - just store all order states
        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          _lastOrderStates[doc.id] = {
            'status': data['status'] ?? 'assigned',
            'address': _formatAddress(data),
          };
        }
        return;
      }

      final currentOrderIds = snapshot.docs.map((doc) => doc.id).toSet();

      // Check for new orders or status changes
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (data.isEmpty) continue;

        final orderId = doc.id;
        final lastState = _lastOrderStates[orderId];

        if (lastState == null) {
          // New order assigned
          await _createOrderNotification(
            orderId: orderId,
            address: _formatAddress(data),
            status: data['status'] ?? 'assigned',
            type: 'new_assignment',
          );
        } else if (lastState['status'] != data['status']) {
          // Status changed
          await _createOrderNotification(
            orderId: orderId,
            address: _formatAddress(data),
            oldStatus: lastState['status'],
            newStatus: data['status'] ?? 'assigned',
            type: 'status_change',
          );
        }

        // Update last state
        _lastOrderStates[orderId] = {
          'status': data['status'] ?? 'assigned',
          'address': _formatAddress(data),
        };
      }

      // Remove orders that are no longer assigned
      _lastOrderStates.removeWhere((key, value) => !currentOrderIds.contains(key));
    });
  }

  // Create order notification
  Future<void> _createOrderNotification({
    required String orderId,
    required String address,
    String? oldStatus,
    String? newStatus,
    String? status,
    required String type,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    String title;
    String message;

    if (type == 'new_assignment') {
      title = 'New Order Assigned';
      message = 'You have been assigned a new order: $address';
    } else if (type == 'status_change') {
      title = 'Order Status Updated';
      message = 'Order status changed from ${_formatStatus(oldStatus)} to ${_formatStatus(newStatus)}: $address';
    } else {
      title = 'Order Update';
      message = 'Order update: $address';
    }

    await createNotification(
      userId: currentUser.uid,
      type: 'order',
      title: title,
      message: message,
      actionType: 'view_order',
      actionData: {'orderId': orderId},
      metadata: {
        'orderStatus': newStatus ?? status,
        'address': address,
      },
    );
  }

  // Setup listeners for message changes
  Future<void> _setupMessageListeners() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Clean up existing listeners
    for (var listener in _messageListeners.values) {
      await listener.cancel();
    }
    _messageListeners.clear();

    // Get all user conversations
    final conversations = await _chatService.getUserConversations().first;

    for (var convDoc in conversations.docs) {
      final convData = convDoc.data() as Map<String, dynamic>;
      final participants = List<String>.from(convData['participants'] ?? []);
      final otherUserId = participants.firstWhere(
        (id) => id != currentUser.uid,
        orElse: () => '',
      );

      if (otherUserId.isEmpty) continue;

      // Listen to messages in this conversation
      final listener = _db
          .collection('conversations')
          .doc(convDoc.id)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.docs.isEmpty) return;

        final messageDoc = snapshot.docs.first;
        final messageData = messageDoc.data() as Map<String, dynamic>;
        final senderId = messageData['senderId'] as String?;

        // Only notify for messages from others
        if (senderId == null || senderId == currentUser.uid) return;

        // Check if notification already exists for this message
        final existing = await _db
            .collection('notifications')
            .where('userId', isEqualTo: currentUser.uid)
            .where('type', isEqualTo: 'message')
            .where('actionData.conversationId', isEqualTo: convDoc.id)
            .where('timestamp', isGreaterThan: Timestamp.fromDate(
              DateTime.now().subtract(const Duration(minutes: 1)),
            ))
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) return;

        // Get sender name
        final senderData = await _chatService.getUserDetails(senderId);
        final senderName = senderData?['name'] ?? senderData?['email'] ?? 'Someone';

        final messageText = messageData['message'] as String? ?? '';
        final preview = messageText.length > 50 
            ? '${messageText.substring(0, 50)}...' 
            : messageText;

        await createNotification(
          userId: currentUser.uid,
          type: 'message',
          title: 'New message from $senderName',
          message: preview,
          actionType: 'open_chat',
          actionData: {
            'conversationId': convDoc.id,
            'otherUserId': otherUserId,
          },
          metadata: {
            'senderName': senderName,
            'senderId': senderId,
            'messageId': messageDoc.id,
          },
        );
      });

      _messageListeners[convDoc.id] = listener;
    }
  }

  // Format address from order data
  String _formatAddress(Map<String, dynamic> data) {
    final street = data['streetAddress'] ?? '';
    final city = data['city'] ?? '';
    final state = data['state'] ?? '';
    final zip = data['zipCode'] ?? '';
    return '$street, $city, $state $zip'.trim();
  }

  // Format status for display
  String _formatStatus(String? status) {
    if (status == null) return 'Unknown';
    return status.replaceAll('_', ' ').toUpperCase();
  }

  // Create notification in Firestore
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
        'type': type, // 'order' | 'message' | 'system' | 'news'
        'title': title,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'actionType': actionType, // 'view_order' | 'open_chat' | 'none' | 'view_update'
        'actionData': actionData ?? {},
        'metadata': metadata ?? {},
      });
    } catch (e) {
      print('Error creating notification: $e');
    }
  }

  // Mark notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _db.collection('notifications').doc(notificationId).update({
        'isRead': true,
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  // Mark all notifications as read
  Future<void> markAllAsRead() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final notifications = await _db
          .collection('notifications')
          .where('userId', isEqualTo: currentUser.uid)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (var doc in notifications.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  // Get unread count stream
  Stream<int> getUnreadCount() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return Stream.value(0);
    }

    return _db
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get all notifications stream
  Stream<QuerySnapshot> getNotifications() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return _db
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Cleanup listeners
  Future<void> dispose() async {
    await _orderListener?.cancel();
    for (var listener in _messageListeners.values) {
      await listener.cancel();
    }
    _messageListeners.clear();
    _lastOrderStates.clear();
    _isInitialized = false;
    _currentUserId = null;
  }
}

