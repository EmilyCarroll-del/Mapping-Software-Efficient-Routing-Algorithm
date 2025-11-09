import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/order.dart' as app_order;
import '../models/route_optimization.dart';
import '../models/delivery_address.dart';
import '../services/aws_route_service.dart';
import '../services/geocoding_service.dart';
import '../services/chat_service.dart';
import 'chat_page.dart';
import 'route_preview_screen.dart';

class DriverAssignedOrdersScreen extends StatefulWidget {
  const DriverAssignedOrdersScreen({super.key});

  @override
  State<DriverAssignedOrdersScreen> createState() =>
      _DriverAssignedOrdersScreenState();
}

class _DriverAssignedOrdersScreenState
    extends State<DriverAssignedOrdersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChatService _chatService = ChatService();
  User? _currentUser;

  StreamSubscription? _addressesSubscription;
  StreamSubscription? _ordersSubscription;
  final _ordersController = StreamController<List<app_order.Order>>();
  List<app_order.Order> _addressDocs = [];
  List<app_order.Order> _orderDocs = [];

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
        if (user != null) {
          _listenToStreams();
        } else {
          _cancelSubscriptions();
        }
      }
    });

    if (_currentUser != null) {
      _listenToStreams();
    }
  }

  void _listenToStreams() {
    _cancelSubscriptions(); // Cancel any existing subscriptions

    final statuses = ['assigned', 'accepted', 'in_progress'];

    _addressesSubscription = _firestore
        .collection('addresses')
        .where('driverId', isEqualTo: _currentUser!.uid)
        .where('status', whereIn: statuses)
        .snapshots()
        .listen((snapshot) {
      _addressDocs = snapshot.docs
          .map((doc) => app_order.Order.fromAddressDoc(doc))
          .toList();
      _combineAndSort();
    });

    _ordersSubscription = _firestore
        .collection('orders')
        .where('driverIds', arrayContains: _currentUser!.uid)
        .where('status', whereIn: statuses)
        .snapshots()
        .listen((snapshot) {
      _orderDocs = snapshot.docs
          .map((doc) => app_order.Order.fromOrderDoc(doc))
          .toList();
      _combineAndSort();
    });
  }

  void _combineAndSort() {
    final allOrders = [..._addressDocs, ..._orderDocs];
    allOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (!_ordersController.isClosed) {
      _ordersController.add(allOrders);
    }
  }

  void _cancelSubscriptions() {
    _addressesSubscription?.cancel();
    _ordersSubscription?.cancel();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _ordersController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assigned Orders')),
        body:
            const Center(child: Text('Please log in to view assigned orders.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned Orders'),
        backgroundColor: const Color(0xFF0D2B0D),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<app_order.Order>>(
        stream: _ordersController.stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No assigned orders',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('You will see your assigned orders here',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final orders = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              if (order.sourceCollection == 'orders') {
                return _buildOrderCard(order);
              } else {
                return _buildAddressCard(order);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(app_order.Order order) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.status.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  DateFormat('MM/dd/yyyy').format(order.createdAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Order ID: ${order.id}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            const Text('PICKUP',
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              order.pickupAddress.fullAddress,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (order.pickupAddress.notes != null &&
                order.pickupAddress.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.note, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.pickupAddress.notes!,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (order.status == 'assigned')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptOrder(order),
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _denyOrder(order),
                      icon: const Icon(Icons.close),
                      label: const Text('Deny'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              )
            else if (order.status == 'accepted' ||
                order.status == 'in_progress')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.dropOffAddresses.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text('DROP-OFFS',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...order.dropOffAddresses.map((address) => Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(address.fullAddress,
                                  style: const TextStyle(fontSize: 16)),
                              if (address.notes != null &&
                                  address.notes!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.note,
                                        size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        address.notes!,
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              ]
                            ],
                          ),
                        )),
                  ],
                  if (order.notes != null && order.notes!.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text('GENERAL NOTES',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(order.notes!, style: const TextStyle(fontSize: 16)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openChatForOrder(order),
                          icon: const Icon(Icons.chat, size: 18),
                          label: const Text('Chat'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            print('🚀 START DELIVERY BUTTON CLICKED');
                            print('Order ID: ${order.id}');
                            print('Order Status: ${order.status}');
                            print(
                                'Order Source Collection: ${order.sourceCollection}');
                            print(
                                'Pickup Address: ${order.pickupAddress.fullAddress}');
                            print(
                                'Drop-off Addresses Count: ${order.dropOffAddresses.length}');
                            try {
                              _updateOrderStatus(order, order.status);
                            } catch (e, stackTrace) {
                              print('❌ ERROR in button handler: $e');
                              print('Stack trace: $stackTrace');
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            }
                          },
                          child: Text(order.status == 'accepted'
                              ? 'Start Delivery'
                              : 'Mark as Completed'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(app_order.Order order) {
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
                    color: _getStatusColor(order.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.status.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MM/dd/yyyy').format(order.createdAt),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.pickupAddress.fullAddress,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.note, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.notes!,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (order.status.toLowerCase() == 'assigned')
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptOrder(order),
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _denyOrder(order),
                      icon: const Icon(Icons.close),
                      label: const Text('Deny'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openChatForOrder(order),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('Chat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        print(
                            '🚀 START DELIVERY BUTTON CLICKED (Address Card)');
                        print('Order ID: ${order.id}');
                        print('Order Status: ${order.status}');
                        print(
                            'Order Source Collection: ${order.sourceCollection}');
                        print(
                            'Pickup Address: ${order.pickupAddress.fullAddress}');
                        print(
                            'Drop-off Addresses Count: ${order.dropOffAddresses.length}');
                        try {
                          _updateOrderStatus(order, order.status);
                        } catch (e, stackTrace) {
                          print('❌ ERROR in button handler (Address Card): $e');
                          print('Stack trace: $stackTrace');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        }
                      },
                      child: Text(order.status == 'accepted'
                          ? 'Start Delivery'
                          : 'Mark as Completed'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Future<void> _acceptOrder(app_order.Order order) async {
    try {
      await _firestore.collection(order.sourceCollection).doc(order.id).update({
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error accepting order: $e')));
    }
  }

  Future<void> _denyOrder(app_order.Order order) async {
    try {
      if (order.sourceCollection == 'orders') {
        await _firestore.collection('orders').doc(order.id).update({
          'driverIds': FieldValue.arrayRemove([_currentUser!.uid]),
          'status': 'denied',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _firestore.collection('addresses').doc(order.id).update({
          'driverId': null,
          'status': 'denied',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error denying order: $e')));
    }
  }

  Future<void> _openChatForOrder(app_order.Order order) async {
    if (!mounted || _currentUser == null) {
      print('_openChatForOrder: Not mounted or no current user');
      return;
    }

    BuildContext? dialogContext;

    try {
      print('_openChatForOrder: Starting chat for order ${order.id}');

      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogContext = context;
          return const Center(child: CircularProgressIndicator());
        },
      );

      // Get order document to find admin user ID (order issuer)
      print(
          '_openChatForOrder: Fetching order document from ${order.sourceCollection}/${order.id}');
      final orderDoc = await _firestore
          .collection(order.sourceCollection)
          .doc(order.id)
          .get();

      if (!orderDoc.exists) {
        throw Exception('Order document not found');
      }

      final orderData = orderDoc.data();
      print('_openChatForOrder: Order data keys: ${orderData?.keys.toList()}');

      String? adminUserId;

      // Try different fields that might contain admin/issuer ID
      if (orderData != null) {
        adminUserId = orderData['createdBy'] as String? ??
            orderData['adminId'] as String? ??
            orderData['adminUserId'] as String? ??
            orderData['userId'] as String? ??
            orderData['issuerId'] as String?;
        print('_openChatForOrder: Found adminUserId from order: $adminUserId');
      }

      // If no admin ID in order, try to find admin users with same company code
      if (adminUserId == null && _currentUser != null) {
        print(
            '_openChatForOrder: No admin ID in order, searching by company code');
        try {
          final currentUserDoc =
              await _firestore.collection('users').doc(_currentUser!.uid).get();
          final currentUserData = currentUserDoc.data();
          final companyCode = currentUserData?['companyCode'] as String?;

          print('_openChatForOrder: Current user company code: $companyCode');

          if (companyCode != null) {
            // Find admin user with same company code
            final adminUsers = await _firestore
                .collection('users')
                .where('companyCode', isEqualTo: companyCode)
                .where('userType', isEqualTo: 'admin')
                .limit(1)
                .get();

            print(
                '_openChatForOrder: Found ${adminUsers.docs.length} admin users');

            if (adminUsers.docs.isNotEmpty) {
              adminUserId = adminUsers.docs.first.id;
              print('_openChatForOrder: Using admin user ID: $adminUserId');
            }
          }
        } catch (e) {
          print('_openChatForOrder: Error finding admin user: $e');
        }
      }

      // Close loading dialog
      if (dialogContext != null && mounted) {
        Navigator.pop(dialogContext!); 
        dialogContext = null;
      }

      if (!mounted) {
        print('_openChatForOrder: Widget not mounted after loading');
        return;
      }

      if (adminUserId == null || adminUserId.isEmpty) {
        print('_openChatForOrder: Could not find admin user ID');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not find admin user for this order. Please contact support.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      print('_openChatForOrder: Getting admin user details for $adminUserId');
      // Get admin user details
      final adminUserData = await _chatService.getUserDetails(adminUserId);
      final adminUserName =
          adminUserData?['name'] ?? adminUserData?['email'] ?? 'Admin';

      print('_openChatForOrder: Admin user name: $adminUserName');

      print('_openChatForOrder: Creating/getting conversation');
      // Create or get conversation
      final conversationId = await _chatService.createOrGetConversation(
        adminUserId,
        orderId: order.id,
        orderTitle: 'Order ${order.id}',
      );

      print('_openChatForOrder: Conversation ID: $conversationId');

      if (!mounted) {
        print('_openChatForOrder: Widget not mounted before navigation');
        return;
      }

      print('_openChatForOrder: Navigating to ChatPage');
      // Navigate to chat page
      // adminUserId is guaranteed to be non-null at this point due to the check above
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatPage(
            conversationId: conversationId,
            otherUserId: adminUserId!,
            otherUserName: adminUserName,
            orderId: order.id,
            orderTitle: 'Order ${order.id}',
            isOldFormat: false,
          ),
        ),
      );

      print('_openChatForOrder: Navigation completed');
    } catch (e, stackTrace) {
      print('_openChatForOrder: ERROR - $e');
      print('_openChatForOrder: Stack trace: $stackTrace');

      // Close loading dialog if still open
      if (dialogContext != null && mounted) {
        try {
          Navigator.pop(dialogContext!); 
        } catch (_) {}
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening chat: ${e.toString()}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateOrderStatus(
      app_order.Order order, String currentStatus) async {
    print('📋 _updateOrderStatus called');
    print('Order ID: ${order.id}');
    print('Current Status: $currentStatus');
    print('Order Status: ${order.status}');

    try {
      // If status is 'accepted', trigger routing instead of directly updating
      if (currentStatus.toLowerCase() == 'accepted') {
        print('✅ Status is accepted, calling _startDeliveryRouting');
        await _startDeliveryRouting(order);
        return;
      }

      print('Status is not accepted, checking for other status updates');

      // For 'in_progress', mark as completed
      String newStatus;
      switch (currentStatus.toLowerCase()) {
        case 'in_progress':
          newStatus = 'completed';
          print('Updating status from in_progress to completed');
          break;
        default:
          print('No status update needed for: ${currentStatus.toLowerCase()}');
          return;
      }
      await _firestore.collection(order.sourceCollection).doc(order.id).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Order status updated successfully to: $newStatus');
    } catch (e, stackTrace) {
      print('❌ ERROR in _updateOrderStatus: $e');
      print('Stack trace: $stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating order: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _startDeliveryRouting(app_order.Order order) async {
    print('🗺️ _startDeliveryRouting STARTED');
    print('Order ID: ${order.id}');
    print('Order Status: ${order.status}');
    print('Mounted: $mounted');

    if (!mounted) {
      print('❌ Widget not mounted, returning');
      return;
    }

    // Show loading dialog
    BuildContext? dialogContext;
    print('📱 Showing loading dialog...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogBuildContext) {
        dialogContext = dialogBuildContext;
        print('✅ Loading dialog builder called');
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Calculating route...'),
                ],
              ),
            ),
          ),
        );
      },
    );
    print('✅ Loading dialog shown');

    try {
      // Get addresses
      print('📍 Getting addresses from order...');
      final pickupAddress = order.pickupAddress;
      final dropOffAddresses = order.dropOffAddresses;

      print('Pickup Address: ${pickupAddress.fullAddress}');
      print('Pickup has coordinates: ${pickupAddress.hasCoordinates}');
      if (pickupAddress.hasCoordinates) {
        print(
            'Pickup coordinates: ${pickupAddress.latitude}, ${pickupAddress.longitude}');
      }
      print('Drop-off addresses count: ${dropOffAddresses.length}');

      if (dropOffAddresses.isEmpty) {
        print('❌ No drop-off addresses found');
        if (!mounted) return;
        if (dialogContext != null) {
          Navigator.pop(dialogContext!); 
          print('✅ Closed loading dialog');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No drop-off address found for this order'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Ensure addresses have coordinates
      print('🌍 Ensuring addresses have coordinates...');
      var pickup = pickupAddress;
      if (!pickup.hasCoordinates) {
        print('⚠️ Pickup address lacks coordinates, geocoding...');
        if (!mounted) return;
        if (dialogContext != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Geocoding pickup address...')),
          );
        }
        try {
          pickup = await GeocodingService.geocodeAddress(pickup);
          print('✅ Pickup geocoded: ${pickup.latitude}, ${pickup.longitude}');
        } catch (e) {
          print('❌ Geocoding pickup failed: $e');
          throw Exception('Failed to geocode pickup address: $e');
        }
      } else {
        print('✅ Pickup already has coordinates');
      }

      // Handle multiple drop-offs - use all of them for routing
      print('📍 Processing ${dropOffAddresses.length} drop-off addresses...');
      final addressesForRouting = <DeliveryAddress>[pickup];
      for (int i = 0; i < dropOffAddresses.length; i++) {
        var dropOff = dropOffAddresses[i];
        print(
            'Processing drop-off ${i + 1}/${dropOffAddresses.length}: ${dropOff.fullAddress}');
        print('Has coordinates: ${dropOff.hasCoordinates}');

        if (!dropOff.hasCoordinates) {
          print('⚠️ Drop-off ${i + 1} lacks coordinates, geocoding...');
          if (!mounted) return;
          try {
            dropOff = await GeocodingService.geocodeAddress(dropOff);
            print(
                '✅ Drop-off ${i + 1} geocoded: ${dropOff.latitude}, ${dropOff.longitude}');
          } catch (e) {
            print('❌ Geocoding drop-off ${i + 1} failed: $e');
            throw Exception('Failed to geocode drop-off address ${i + 1}: $e');
          }
        } else {
          print('✅ Drop-off ${i + 1} already has coordinates');
        }
        addressesForRouting.add(dropOff);
      }

      print(
          '✅ All addresses processed. Total addresses for routing: ${addressesForRouting.length}');

      // Initialize AWS Route Service
      print('🔧 Initializing AWS Route Service...');
      final awsService = AwsRouteService();
      print('AWS Service available: ${awsService.isAvailable}');

      if (!awsService.isAvailable) {
        print('⚠️ AWS Route Service not available, initializing...');
        try {
          await awsService.initialize();
          print('✅ AWS Route Service initialized successfully');
          print('AWS Service now available: ${awsService.isAvailable}');
        } catch (initError, initStack) {
          print('❌ Failed to initialize AWS Route Service: $initError');
          print('Stack trace: $initStack');
          if (!mounted) return;
          if (dialogContext != null && Navigator.canPop(dialogContext!)) {
            Navigator.pop(dialogContext!); 
            print('✅ Closed loading dialog after init failure');
          }
          throw Exception(
              'Failed to initialize AWS Route Service. Please check your .env file and AWS configuration.');
        }
      } else {
        print('✅ AWS Route Service already available');
      }

      print(
          '🗺️ Calculating AWS route for ${addressesForRouting.length} addresses');
      print(
          'Pickup: ${pickup.fullAddress} (${pickup.latitude}, ${pickup.longitude})');
      for (int i = 0; i < dropOffAddresses.length; i++) {
        final dropOff = addressesForRouting[i + 1];
        print(
            'Drop-off ${i + 1}: ${dropOff.fullAddress} (${dropOff.latitude}, ${dropOff.longitude})');
      }

      // Calculate route using AWS (with all drop-offs as waypoints)
      print('⏳ Calling AWS calculateRoute...');
      final routeOptimization = await awsService.calculateRoute(
        addresses: addressesForRouting,
        startAddress: pickup,
        travelMode: 'Truck',
        optimizationMode: 'FastestRoute',
      );

      print('✅ AWS route calculated successfully');
      print('Total distance: ${routeOptimization.totalDistance} km');
      print('Estimated time: ${routeOptimization.estimatedTime}');
      print('Route steps: ${routeOptimization.optimizedRoute?.length ?? 0}');

      if (!mounted) {
        print('❌ Widget not mounted after route calculation');
        return;
      }

      if (dialogContext != null) {
        Navigator.pop(dialogContext!); 
        print('✅ Closed loading dialog');
      }

      // Navigate to in-app route preview screen
      print('📱 Navigating to route preview screen...');
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RoutePreviewScreen(
            routeOptimization: routeOptimization,
            order: order,
          ),
        ),
      );
      print('✅ Route preview screen shown');
    } catch (e, stackTrace) {
      print('❌ Error in _startDeliveryRouting: $e');
      print('Stack trace: $stackTrace');

      if (!mounted) {
        print('❌ Widget not mounted, cannot show error');
        return;
      }

      if (dialogContext != null && Navigator.canPop(dialogContext!)) {
        Navigator.pop(dialogContext!); 
        print('✅ Closed loading dialog after error');
      }

      // Provide more specific error messages
      String errorMessage = 'Route calculation failed';
      bool isAwsError = false;
      bool fallbackUsed = false;

      if (e.toString().contains('AWS Route Service not initialized')) {
        errorMessage =
            'AWS Route Service not configured. Please check your .env file.';
        isAwsError = true;
      } else if (e.toString().contains('AWS API error')) {
        errorMessage =
            'AWS API error. Please verify your API key has CalculateRoutes permission.';
        isAwsError = true;
      } else if (e.toString().contains('Fallback route used')) {
        errorMessage = e.toString();
        isAwsError = true;
        fallbackUsed = true;
      } else if (e.toString().contains('DNS failure') ||
          e.toString().contains('Cannot reach AWS servers')) {
        errorMessage =
            'Cannot reach AWS routing servers. Check network connectivity or test on a real device.';
        isAwsError = true;
      } else if (e.toString().contains('coordinates')) {
        errorMessage =
            'Address geocoding failed. Please check the addresses are valid.';
      } else {
        errorMessage = 'Route calculation failed: ${e.toString()}';
      }

      print('Error message: $errorMessage');
      print('Is AWS error: $isAwsError');

      final shouldShowBanner = !fallbackUsed;

      if (mounted && shouldShowBanner) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: isAwsError ? Colors.orange : Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // If AWS fails but we have addresses, create a fallback route
      if (isAwsError) {
        try {
          print('🔄 Attempting to create fallback route...');
          final pickupAddress = order.pickupAddress;
          final dropOffAddresses = order.dropOffAddresses;

          if (dropOffAddresses.isNotEmpty) {
            // Create a simple route optimization with pickup and drop-off
            var pickup = pickupAddress;
            if (!pickup.hasCoordinates) {
              pickup = await GeocodingService.geocodeAddress(pickup);
            }

            var dropOff = dropOffAddresses.first;
            if (!dropOff.hasCoordinates) {
              dropOff = await GeocodingService.geocodeAddress(dropOff);
            }

            if (pickup.hasCoordinates && dropOff.hasCoordinates) {
              print(
                  '✅ Creating fallback route from ${pickup.fullAddress} to ${dropOff.fullAddress}');

              // Calculate simple distance
              final lat1 = pickup.latitude!;
              final lon1 = pickup.longitude!;
              final lat2 = dropOff.latitude!;
              final lon2 = dropOff.longitude!;

              // Haversine formula for distance
              final dLat = (lat2 - lat1) * pi / 180;
              final dLon = (lon2 - lon1) * pi / 180;
              final a = sin(dLat / 2) * sin(dLat / 2) +
                  cos(lat1 * pi / 180) *
                      cos(lat2 * pi / 180) *
                      sin(dLon / 2) *
                      sin(dLon / 2);
              final c = 2 * atan2(sqrt(a), sqrt(1 - a));
              final distance = 6371 * c; // Earth radius in km

              // Estimate time (assuming 50 km/h average)
              final estimatedSeconds = (distance / 50 * 3600).round();

              // Create simple route steps
              final routeSteps = <RouteStep>[
                RouteStep(
                  sequenceNumber: 1,
                  address: pickup,
                  distanceFromPrevious: 0,
                  estimatedTravelTime: const Duration(seconds: 0),
                  instructions: 'Start at ${pickup.fullAddress}',
                ),
                RouteStep(
                  sequenceNumber: 2,
                  address: dropOff,
                  distanceFromPrevious: distance,
                  estimatedTravelTime: Duration(seconds: estimatedSeconds),
                  instructions: 'Deliver to ${dropOff.fullAddress}',
                ),
              ];

              final geometry = <List<double>>[];
              for (int i = 0; i <= 10; i++) {
                final fraction = i / 10.0;
                final lat = lat1 + (lat2 - lat1) * fraction;
                final lng = lon1 + (lon2 - lon1) * fraction;
                geometry.add([lat, lng]);
              }

              final fallbackRoute = RouteOptimization(
                name: 'Fallback Route (AWS Unavailable)',
                addresses: [pickup, dropOff],
                algorithm: RouteAlgorithm.nearestNeighbor,
                optimizedRoute: routeSteps,
                totalDistance: distance,
                estimatedTime: Duration(seconds: estimatedSeconds),
                routeGeometry: geometry,
                completedAt: DateTime.now(),
              );

              print(
                  '✅ Fallback route created: ${fallbackRoute.totalDistance} km, ${fallbackRoute.estimatedTime}');

              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RoutePreviewScreen(
                      routeOptimization: fallbackRoute,
                      order: order,
                    ),
                  ),
                );
              }
              return;
            }
          }
        } catch (fallbackError) {
          print('❌ Fallback route creation also failed: $fallbackError');
        }

        if (fallbackUsed) return;

        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Route Unavailable'),
              content: Text(errorMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Route Unavailable'),
            content: Text(errorMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'N/A';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
