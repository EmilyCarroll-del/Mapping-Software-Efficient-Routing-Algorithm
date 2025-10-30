import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../colors.dart';
import '../services/notification_service.dart';
import 'chat_page.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  String _filterType = 'all'; // 'all', 'order', 'message', 'system', 'news'

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Please log in to view notifications.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
            onPressed: () => _markAllAsRead(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterTabs(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _getNotificationsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading notifications',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                final notifications = snapshot.data!.docs;
                final groupedNotifications = _groupNotificationsByDate(notifications);

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: ListView.builder(
                    itemCount: groupedNotifications.length,
                    itemBuilder: (context, index) {
                      final group = groupedNotifications[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              group['header'] as String,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                          ...(group['notifications'] as List<DocumentSnapshot>)
                              .map((notification) => _buildNotificationTile(notification))
                              .toList(),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _buildFilterChip('All', 'all'),
            _buildFilterChip('Orders', 'order'),
            _buildFilterChip('Messages', 'message'),
            _buildFilterChip('Updates', 'system'),
            _buildFilterChip('News', 'news'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String type) {
    final isSelected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _filterType = type;
          });
        },
        selectedColor: kPrimaryColor.withOpacity(0.2),
        checkmarkColor: kPrimaryColor,
        labelStyle: TextStyle(
          color: isSelected ? kPrimaryColor : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _getNotificationsStream() {
    if (_filterType == 'all') {
      return _notificationService.getNotifications();
    }
    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Stream.empty();
    }

    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .where('type', isEqualTo: _filterType)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  List<Map<String, dynamic>> _groupNotificationsByDate(List<QueryDocumentSnapshot> notifications) {
    final groups = <String, List<DocumentSnapshot>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeek = today.subtract(const Duration(days: 7));

    for (var notification in notifications) {
      final data = notification.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] as Timestamp?;
      if (timestamp == null) continue;

      final date = timestamp.toDate();
      final dateOnly = DateTime(date.year, date.month, date.day);

      String header;
      if (dateOnly == today) {
        header = 'Today';
      } else if (dateOnly == yesterday) {
        header = 'Yesterday';
      } else if (date.isAfter(thisWeek)) {
        header = 'This Week';
      } else {
        header = 'Older';
      }

      groups.putIfAbsent(header, () => []).add(notification);
    }

    // Return in order: Today, Yesterday, This Week, Older
    final orderedHeaders = ['Today', 'Yesterday', 'This Week', 'Older'];
    return orderedHeaders
        .where((header) => groups.containsKey(header))
        .map((header) => {
              'header': header,
              'notifications': groups[header]!,
            })
        .toList();
  }

  Widget _buildNotificationTile(DocumentSnapshot notification) {
    final data = notification.data() as Map<String, dynamic>;
    final title = data['title'] ?? 'Notification';
    final message = data['message'] ?? '';
    final type = data['type'] ?? 'system';
    final timestamp = data['timestamp'] != null
        ? (data['timestamp'] as Timestamp).toDate()
        : DateTime.now();
    final isRead = data['isRead'] ?? false;
    final actionType = data['actionType'] ?? 'none';
    final actionData = data['actionData'] as Map<String, dynamic>? ?? {};
    final metadata = data['metadata'] as Map<String, dynamic>? ?? {};

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : kPrimaryColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRead ? Colors.grey[200]! : kPrimaryColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: () => _handleNotificationTap(
          notification,
          actionType,
          actionData,
          metadata,
        ),
        leading: CircleAvatar(
          backgroundColor: _getTypeColor(type).withOpacity(0.2),
          child: Icon(
            _getNotificationIcon(type),
            color: _getTypeColor(type),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  _formatTimestamp(timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleNotificationTap(
    DocumentSnapshot notification,
    String actionType,
    Map<String, dynamic> actionData,
    Map<String, dynamic> metadata,
  ) async {
    // Mark as read
    await _notificationService.markAsRead(notification.id);

    // Navigate based on action type
    if (!mounted) return;

    switch (actionType) {
      case 'view_order':
        final orderId = actionData['orderId'] as String?;
        if (orderId != null) {
          context.go('/assigned-orders');
        }
        break;

      case 'open_chat':
        final conversationId = actionData['conversationId'] as String?;
        final otherUserId = actionData['otherUserId'] as String?;
        final senderName = metadata['senderName'] as String? ?? 'User';
        
        if (conversationId != null && otherUserId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                conversationId: conversationId,
                otherUserId: otherUserId,
                otherUserName: senderName,
                isOldFormat: false,
              ),
            ),
          );
        }
        break;

      case 'view_update':
        final url = actionData['url'] as String?;
        if (url != null) {
          // Handle URL opening (you can use url_launcher package)
          print('Open URL: $url');
        }
        break;

      default:
        // Just mark as read, no navigation
        break;
    }
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (_filterType) {
      case 'order':
        message = 'No order notifications';
        icon = Icons.local_shipping;
        break;
      case 'message':
        message = 'No message notifications';
        icon = Icons.message;
        break;
      case 'system':
        message = 'No system notifications达成';
        icon = Icons.settings;
        break;
      case 'news':
        message = 'No news notifications';
        icon = Icons.newspaper;
        break;
      default:
        message = 'No notifications';
        icon = Icons.notifications_none;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You will receive notifications here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllAsRead() async {
    await _notificationService.markAllAsRead();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All notifications marked as read'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'order':
        return Icons.local_shipping;
      case 'message':
        return Icons.message;
      case 'system':
        return Icons.settings;
      case 'news':
        return Icons.newspaper;
      default:
        return Icons.notifications;
    }
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'order':
        return Colors.orange;
      case 'message':
        return Colors.blue;
      case 'system':
        return Colors.grey;
      case 'news':
        return Colors.green;
      default:
        return kPrimaryColor;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
}
