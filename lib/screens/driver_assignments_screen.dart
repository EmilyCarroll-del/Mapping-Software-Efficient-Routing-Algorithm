import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../models/delivery_address.dart';
import '../models/order_model.dart';
import '../services/aws_route_service.dart';
import '../services/firestore_service.dart';
import '../providers/location_provider.dart';
import 'route_preview_screen.dart';

class DriverAssignmentsScreen extends StatelessWidget {
  const DriverAssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final firestoreService = Provider.of<FirestoreService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assignments'),
      ),
      body: currentUser == null
          ? const Center(child: Text('Please log in to see your assignments.'))
          : StreamBuilder<List<OrderModel>>(
              stream: firestoreService.getDriverOrders(currentUser.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No Assignments Yet'));
                }

                final orders = snapshot.data!;

                return ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    return OrderCard(order: orders[index]);
                  },
                );
              },
            ),
    );
  }
}

class OrderCard extends StatefulWidget {
  final OrderModel order;

  const OrderCard({super.key, required this.order});

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  final AWSRouteService _awsRouteService = AWSRouteService();

  @override
  void initState() {
    super.initState();
    _awsRouteService.initialize();
  }

  Future<void> _calculateAndShowRoute(LocationProvider locationProvider) async {
    if (!locationProvider.isLocationAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current location not available.')),
        );
      }
      return;
    }

    final currentLocation = locationProvider.currentLocation!;
    final startAddress = DeliveryAddress.fromCoordinates(
      latitude: currentLocation.latitude!,
      longitude: currentLocation.longitude!,
    );

    final addresses = [startAddress, widget.order.pickUpAddress, ...widget.order.dropOffAddresses];

    try {
      final route = await _awsRouteService.calculateRoute(
        addresses: addresses,
        travelMode: 'Truck',
      );

      if (mounted) {
        Provider.of<FirestoreService>(context, listen: false)
            .updateOrderStatus(widget.order.orderId, 'in_progress');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RoutePreviewScreen(
              routeOptimization: route,
              order: widget.order,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error calculating route: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final currentUser = FirebaseAuth.instance.currentUser;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order ID: ${widget.order.orderId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Status: ${widget.order.status}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Pickup: ${widget.order.pickUpAddress.fullAddress}'),
                  if (widget.order.status == 'accepted' || widget.order.status == 'in_progress') ...[
                    const SizedBox(height: 8),
                    const Text('Drop-off(s):', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...widget.order.dropOffAddresses.map((address) => Text(address.fullAddress)),
                    const SizedBox(height: 8),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (widget.order.pickUpAddress.notes != null &&
                        widget.order.pickUpAddress.notes!.isNotEmpty)
                      Text(widget.order.pickUpAddress.notes!),
                    ...widget.order.dropOffAddresses.map((address) {
                      if (address.notes != null && address.notes!.isNotEmpty) {
                        return Text(address.notes!);
                      } else {
                        return const SizedBox.shrink();
                      }
                    }),
                  ],
                ],
              ),
            ),
            _buildActionButtons(context, firestoreService, locationProvider, currentUser),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    FirestoreService firestoreService,
    LocationProvider locationProvider,
    User? currentUser,
  ) {
    switch (widget.order.status) {
      case 'assigned':
        return Row(
          children: [
            ElevatedButton(
              onPressed: () => firestoreService.updateOrderStatus(widget.order.orderId, 'accepted'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Accept'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => firestoreService.denyOrder(widget.order.orderId, currentUser!.uid),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Deny'),
            ),
          ],
        );
      case 'accepted':
        return ElevatedButton(
          onPressed: () => _calculateAndShowRoute(locationProvider),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Start Driving'),
        );
      case 'in_progress':
        return ElevatedButton(
          onPressed: () => firestoreService.updateOrderStatus(widget.order.orderId, 'completed'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Complete Order'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
