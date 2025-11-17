
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
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
  final AWSRouteService _awsRouteService = AWSRouteService();
  User? _currentUser;

  StreamSubscription? _addressesSubscription;
  StreamSubscription? _ordersSubscription;
  final _ordersController = StreamController<List<app_order.Order>>();
  List<app_order.Order> _addressDocs = [];
  List<app_order.Order> _orderDocs = [];

  final DeliveryAddress _currentEmulatorLocation = DeliveryAddress(
    streetAddress: 'Hofstra University',
    city: 'Hempstead',
    state: 'NY',
    zipCode: '11549',
    latitude: 40.7143,
    longitude: -73.5994,
  );

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _awsRouteService.initialize();
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
    _cancelSubscriptions();
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
        body: const Center(child: Text('Please log in to view assigned orders.')),
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
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: _getStatusColor(order.status),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(order.status.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))),
                    Text(DateFormat('MM/dd/yyyy').format(order.createdAt),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12))
                  ]),
                  const SizedBox(height: 12),
                  Text('Order ID: ${order.id}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  const Text('PICKUP',
                      style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(order.pickupAddress.fullAddress,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (order.pickupAddress.notes != null &&
                      order.pickupAddress.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.note, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(order.pickupAddress.notes!,
                              style: const TextStyle(color: Colors.grey)))
                    ])
                  ],
                  const SizedBox(height: 16),
                  if (order.status == 'assigned')
                    Row(children: [
                      Expanded(
                          child: ElevatedButton.icon(
                              onPressed: () => _acceptOrder(order),
                              icon: const Icon(Icons.check),
                              label: const Text('Accept'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: ElevatedButton.icon(
                              onPressed: () => _denyOrder(order),
                              icon: const Icon(Icons.close),
                              label: const Text('Deny'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white)))
                    ])
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
                                padding:
                                    const EdgeInsets.only(bottom: 12.0),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(address.fullAddress,
                                          style: const TextStyle(fontSize: 16)),
                                      if (address.notes != null &&
                                          address.notes!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(children: [
                                          const Icon(Icons.note,
                                              size: 16,
                                              color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Expanded(
                                              child: Text(address.notes!,
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 14)))
                                        ])
                                      ]
                                    ])))
                          ],
                          if (order.notes != null &&
                              order.notes!.isNotEmpty) ...[
                            const Divider(height: 24),
                            const Text('GENERAL NOTES',
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(order.notes!, style: const TextStyle(fontSize: 16))
                          ],
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(
                                child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _openChatForOrder(order),
                                    icon: const Icon(Icons.chat, size: 18),
                                    label: const Text('Chat'),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white))),
                            const SizedBox(width: 8),
                            Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                    onPressed: () {
                                      try {
                                        _updateOrderStatus(
                                            order, order.status);
                                      } catch (e, stackTrace) {
                                        print(
                                            '❌ ERROR in button handler: $e');
                                        print('Stack trace: $stackTrace');
                                      }
                                    },
                                    child: Text(order.status == 'accepted'
                                        ? 'Start Delivery'
                                        : 'Mark as Completed')))
                          ])
                        ])
                ])));
  }

  Widget _buildAddressCard(app_order.Order order) {
    return Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 4,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: _getStatusColor(order.status),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(order.status.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold))),
                    const Spacer(),
                    Text(DateFormat('MM/dd/yyyy').format(order.createdAt),
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12))
                  ]),
                  const SizedBox(height: 12),
                  Text(order.pickupAddress.fullAddress,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (order.notes != null && order.notes!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.note, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                          child: Text(order.notes!,
                              style: const TextStyle(color: Colors.grey)))
                    ])
                  ],
                  const SizedBox(height: 16),
                  if (order.status.toLowerCase() == 'assigned')
                    Row(children: [
                      Expanded(
                          child: ElevatedButton.icon(
                              onPressed: () => _acceptOrder(order),
                              icon: const Icon(Icons.check),
                              label: const Text('Accept'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: ElevatedButton.icon(
                              onPressed: () => _denyOrder(order),
                              icon: const Icon(Icons.close),
                              label: const Text('Deny'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white)))
                    ])
                  else
                    Row(children: [
                      Expanded(
                          child: ElevatedButton.icon(
                              onPressed: () =>
                                  _openChatForOrder(order),
                              icon: const Icon(Icons.chat, size: 18),
                              label: const Text('Chat'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white))),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 2,
                          child: ElevatedButton(
                              onPressed: () {
                                try {
                                  _updateOrderStatus(order, order.status);
                                } catch (e, stackTrace) {
                                  print(
                                      '❌ ERROR in button handler (Address Card): $e');
                                  print('Stack trace: $stackTrace');
                                }
                              },
                              child: Text(order.status == 'accepted'
                                  ? 'Start Delivery'
                                  : 'Mark as Completed')))
                    ])
                ])));
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Colors.orange;
      case 'accepted':
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
      await _firestore
          .collection(order.sourceCollection)
          .doc(order.id)
          .update({
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
    if (currentStatus.toLowerCase() == 'accepted') {
      await _startDeliveryRouting(order);
      return;
    }
    String newStatus;
    switch (currentStatus.toLowerCase()) {
      case 'in_progress':
        newStatus = 'completed';
        break;
      default:
        return;
    }
    await _firestore
        .collection(order.sourceCollection)
        .doc(order.id)
        .update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _startDeliveryRouting(app_order.Order order) async {
    print('\n');
    print('======================================================');
    print('🚦 STARTING DELIVERY ROUTING 🚦');
    print('======================================================');
    print('Order ID: ${order.id}');

    if (!mounted) return;

    BuildContext? dialogContext;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogBuildContext) {
          dialogContext = dialogBuildContext;
          return const Center(
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Calculating route...')
                      ]))));
        });

    try {
      var pickup = order.pickupAddress;
      final dropOffs = order.dropOffAddresses;

      final addressesForRouting = <DeliveryAddress>[_currentEmulatorLocation];

      if (!pickup.hasCoordinates) {
        print('  -> Geocoding pickup: ${pickup.fullAddress}');
        pickup = await GeocodingService.geocodeAddress(pickup);
      }
      addressesForRouting.add(pickup);

      for (var dropOff in dropOffs) {
        if (!dropOff.hasCoordinates) {
          print('  -> Geocoding drop-off: ${dropOff.fullAddress}');
          dropOff = await GeocodingService.geocodeAddress(dropOff);
        }
        addressesForRouting.add(dropOff);
      }
      
      print('\n📍 Addresses for routing:');
      for (var addr in addressesForRouting) {
        print('  - ${addr.fullAddress}');
      }
      
      print('\n☁️ Calling AWS Route Service for a \'Truck\' route...');

      final routeOptimization = await _awsRouteService.calculateRoute(
        addresses: addressesForRouting,
        travelMode: 'Truck',
      );

      print('✅ AWS Route calculation successful!');
      print('  - Total Distance: ${routeOptimization.totalDistance?.toStringAsFixed(1)} km');
      print('  - Estimated Time: ${routeOptimization.estimatedTime?.inMinutes} minutes');
      print('  - Route Steps: ${routeOptimization.optimizedRoute?.length ?? 0}');
      print('======================================================\n');

      if (!mounted) return;
      if (dialogContext != null) Navigator.pop(dialogContext!);

      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => RoutePreviewScreen(
            routeOptimization: routeOptimization,
            order: order,
          ),
        ),
      );

      if (mounted && result == 'completed') {
        // Screen will refresh automatically
      }
    } catch (e, stackTrace) {
      print('❌ Error in _startDeliveryRouting: $e');
      print('Stack trace: $stackTrace');
      if (mounted && dialogContext != null) Navigator.pop(dialogContext!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error calculating route: ${e.toString()}'),
            backgroundColor: Colors.red));
      }
    }
  }
}
