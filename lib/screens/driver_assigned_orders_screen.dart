import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/order.dart' as app_order;

class DriverAssignedOrdersScreen extends StatefulWidget {
  const DriverAssignedOrdersScreen({super.key});

  @override
  State<DriverAssignedOrdersScreen> createState() =>
      _DriverAssignedOrdersScreenState();
}

class _DriverAssignedOrdersScreenState extends State<DriverAssignedOrdersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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
      _addressDocs = snapshot.docs.map((doc) => app_order.Order.fromAddressDoc(doc)).toList();
      _combineAndSort();
    });

    _ordersSubscription = _firestore
        .collection('orders')
        .where('driverIds', arrayContains: _currentUser!.uid)
        .where('status', whereIn: statuses)
        .snapshots()
        .listen((snapshot) {
      _orderDocs = snapshot.docs.map((doc) => app_order.Order.fromOrderDoc(doc)).toList();
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
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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
                  Text('No assigned orders', style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('You will see your assigned orders here', style: TextStyle(color: Colors.grey)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.status.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  DateFormat('MM/dd/yyyy').format(order.createdAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Order ID: ${order.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            const Text('PICKUP', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              order.pickupAddress.fullAddress,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (order.pickupAddress.notes != null && order.pickupAddress.notes!.isNotEmpty) ...[
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
            else if (order.status == 'accepted' || order.status == 'in_progress')
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.dropOffAddresses.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text('DROP-OFFS', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...order.dropOffAddresses.map((address) => Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(address.fullAddress, style: const TextStyle(fontSize: 16)),
                          if (address.notes != null && address.notes!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.note, size: 16, color: Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    address.notes!,
                                    style: const TextStyle(color: Colors.grey, fontSize: 14),
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
                    const Text('GENERAL NOTES', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(order.notes!, style: const TextStyle(fontSize: 16)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _updateOrderStatus(order, order.status),
                      child: Text(order.status == 'accepted' ? 'Start Delivery' : 'Mark as Completed'),
                    ),
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _updateOrderStatus(order, order.status),
                  child: Text(order.status == 'accepted' ? 'Start Delivery' : 'Mark as Completed'),
                ),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error accepting order: $e')));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error denying order: $e')));
    }
  }

  Future<void> _updateOrderStatus(app_order.Order order, String currentStatus) async {
    try {
      String newStatus;
      switch (currentStatus.toLowerCase()) {
        case 'accepted':
          newStatus = 'in_progress';
          break;
        case 'in_progress':
          newStatus = 'completed';
          break;
        default:
          return;
      }
      await _firestore.collection(order.sourceCollection).doc(order.id).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating order: $e')));
    }
  }
}
