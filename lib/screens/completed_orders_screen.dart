import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class CompletedOrdersScreen extends StatelessWidget {
  const CompletedOrdersScreen({super.key});

  Widget _buildCompletedBy(BuildContext context, List<String> driverIds) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    if (driverIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<List<UserModel?>>(
      future: Future.wait(driverIds.map((id) => firestoreService.getUserById(id))),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Row(
            children: [
              Text('Completed by: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Loading...'),
            ],
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Row(
            children: [
              Text('Completed by: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Error loading drivers'),
            ],
          );
        }

        final drivers = snapshot.data!.where((user) => user != null).cast<UserModel>();
        final driverEmails = drivers.map((d) => d.email ?? 'No Email').join(', ');

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Completed by: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(driverEmails)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final user = Provider.of<AuthProvider>(context).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completed Orders'),
      ),
      body: user == null
          ? const Center(child: Text('Please log in to view completed orders.'))
          : StreamBuilder<List<OrderModel>>(
              stream: firestoreService.getCompletedOrders(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No completed orders found.'));
                }

                final orders = snapshot.data!;

                return ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Order ID: ${order.orderId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text('Status: ${order.status}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  _buildCompletedBy(context, order.driverIds),
                                  const SizedBox(height: 8),
                                  Text('Pickup: ${order.pickUpAddress.fullAddress}'),
                                  const SizedBox(height: 8),
                                  const Text('Drop-off(s):', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ...order.dropOffAddresses.map((address) => Text(address.fullAddress)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => firestoreService.reassignOrder(order.orderId),
                              child: const Text('Reassign'),
                            ),
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
}
