import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../models/delivery_address.dart';
import '../services/geocoding_service.dart';

class DriverAssignedOrdersScreen extends StatefulWidget {
  const DriverAssignedOrdersScreen({super.key});

  @override
  State<DriverAssignedOrdersScreen> createState() =>
      _DriverAssignedOrdersScreenState();
}

class _DriverAssignedOrdersScreenState
    extends State<DriverAssignedOrdersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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
            .where('status', whereIn: ['assigned', 'in_progress'])
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

          final allActiveOrders = snapshot.data!.docs;
          final inProgressOrders = allActiveOrders.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['status'] == 'in_progress';
          }).toList();

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: allActiveOrders.length,
                  itemBuilder: (context, index) {
                    final orderData =
                        allActiveOrders[index].data() as Map<String, dynamic>;
                    final orderId = allActiveOrders[index].id;
                    final deliveryAddress = DeliveryAddress.fromJson(orderData
                      ..['id'] = orderId); // Ensure ID is populated for the model

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
                                    color: _getStatusColor(
                                        orderData['status'] ?? 'assigned'),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    (orderData['status'] ?? 'assigned')
                                        .toUpperCase(),
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
                              deliveryAddress.fullAddress,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (orderData['notes'] != null &&
                                orderData['notes'].isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.note,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      orderData['notes'],
                                      style:
                                          const TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _updateOrderStatus(
                                    orderId, orderData['status'], deliveryAddress),
                                icon: Icon(_getActionIcon(
                                    orderData['status'] ?? 'assigned')),
                                label: Text(_getActionText(
                                    orderData['status'] ?? 'assigned')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D2B0D),
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (inProgressOrders.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final ordersToOptimize = inProgressOrders.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          data['id'] = doc.id;
                          return DeliveryAddress.fromJson(data);
                        }).toList();
                        context.go('/optimized-route-map',
                            extra: ordersToOptimize);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D2B0D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Optimize on Map'),
                    ),
                  ),
                ),
            ],
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

  Future<void> _updateOrderStatus(
      String orderId, String currentStatus, DeliveryAddress address) async {
    try {
      String newStatus;
      Map<String, dynamic> updates = {};

      switch (currentStatus.toLowerCase()) {
        case 'assigned':
          newStatus = 'in_progress';
          DeliveryAddress updatedAddress = address;
          // Geocode the address when starting delivery if it doesn't have coordinates
          if (!address.hasCoordinates) {
            updatedAddress = await GeocodingService.geocodeAddress(address);
          }
          updates['latitude'] = updatedAddress.latitude;
          updates['longitude'] = updatedAddress.longitude;
          break;
        case 'in_progress':
          newStatus = 'completed';
          break;
        default:
          return; // Already completed or invalid status
      }

      updates['status'] = newStatus;
      updates['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('addresses').doc(orderId).update(updates);

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
}
