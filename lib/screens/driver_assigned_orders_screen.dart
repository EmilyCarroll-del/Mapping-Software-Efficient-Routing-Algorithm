import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';
import '../services/chat_service.dart';
import 'chat_page.dart';
import 'package:go_router/go_router.dart';

class DriverAssignedOrdersScreen extends StatefulWidget {
  const DriverAssignedOrdersScreen({super.key});

  @override
  State<DriverAssignedOrdersScreen> createState() => _DriverAssignedOrdersScreenState();
}

class _DriverAssignedOrdersScreenState extends State<DriverAssignedOrdersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assigned Orders')),
        body: const Center(child: Text('Please log in to view assigned orders.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned Orders'),
        backgroundColor: const Color(0xFF0D2B0D),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('addresses')
            .where('driverId', isEqualTo: _currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No assigned orders',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You will see your assigned orders here',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final orders = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final orderData = orders[index].data() as Map<String, dynamic>;
              final orderId = orders[index].id;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(orderData['status'] ?? 'assigned'),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              (orderData['status'] ?? 'assigned').toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatDate(orderData['createdAt']),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${orderData['streetAddress'] ?? ''}, ${orderData['city'] ?? ''}, ${orderData['state'] ?? ''} ${orderData['zipCode'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (orderData['notes'] != null && orderData['notes'].isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.note, size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                orderData['notes'],
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _updateOrderStatus(orderId, orderData['status']),
                          icon: Icon(_getActionIcon(orderData['status'] ?? 'assigned')),
                          label: Text(_getActionText(orderData['status'] ?? 'assigned')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D2B0D),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      // Chat button for accepted orders
                      if ((orderData['status'] == 'assigned' || orderData['status'] == 'in_progress')) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openChatForOrder(orderId, orderData),
                            icon: const Icon(Icons.chat),
                            label: const Text('Chat about this order'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF0D2B0D),
                              side: const BorderSide(color: Color(0xFF0D2B0D)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Icons.play_arrow;
      case 'in_progress':
        return Icons.check;
      case 'completed':
        return Icons.done;
      default:
        return Icons.play_arrow;
    }
  }

  String _getActionText(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return 'Start Delivery';
      case 'in_progress':
        return 'Mark as Completed';
      case 'completed':
        return 'Completed';
      default:
        return 'Start Delivery';
    }
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown date';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is String) {
        date = DateTime.parse(timestamp);
      } else {
        return 'Invalid date';
      }
      
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Future<void> _updateOrderStatus(String orderId, String currentStatus) async {
    try {
      String newStatus;
      switch (currentStatus.toLowerCase()) {
        case 'assigned':
          newStatus = 'in_progress';
          break;
        case 'in_progress':
          newStatus = 'completed';
          break;
        default:
          return; // Already completed or invalid status
      }

      await _firestore.collection('addresses').doc(orderId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order status updated to ${newStatus.replaceAll('_', ' ')}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openChatForOrder(String orderId, Map<String, dynamic> orderData) async {
    if (_currentUser == null) return;

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Get admin ID - try different possible field names
      String? adminId = (orderData['createdBy'] as String?) ??
                        orderData['adminId'] as String? ??
                        orderData['userId'] as String?;

      // If no adminId in order, try to get it from deliveries collection
      if (adminId == null) {
        try {
          final deliveryDoc = await _firestore.collection('deliveries').doc(orderId).get();
          if (deliveryDoc.exists) {
            final deliveryData = deliveryDoc.data();
            adminId = deliveryData?['createdBy'] as String? ??
                      deliveryData?['adminId'] as String? ??
                      deliveryData?['userId'] as String?;
          }
        } catch (e) {
          print('Error getting delivery data: $e');
        }
      }

      if (adminId == null) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to find the order administrator. Please contact support.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Store in non-nullable variable after null check
      final adminIdNonNull = adminId!;

      // Get admin user details
      final adminDetails = await _chatService.getUserDetails(adminIdNonNull);
      if (adminDetails == null) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Administrator not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Create or get conversation
      final orderTitle = '${(orderData['streetAddress'] ?? '').toString().trim()}, ${(orderData['city'] ?? '').toString().trim()}, ${(orderData['state'] ?? '').toString().trim()} ${(orderData['zipCode'] ?? '').toString().trim()}'.trim();
      final conversationId = await _chatService.createOrGetConversation(
        adminIdNonNull.trim(),
        orderId: orderId.trim(),
        orderTitle: orderTitle,
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }

      // Navigate directly to Chat for this order
      if (mounted) {
        context.push('/chat', extra: {
          'conversationId': conversationId,
          'otherUserId': adminIdNonNull,
          'otherUserName': adminDetails['name'] ?? adminDetails['email'] ?? 'Admin',
          'orderId': orderId,
          'orderTitle': orderTitle,
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening chat: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
