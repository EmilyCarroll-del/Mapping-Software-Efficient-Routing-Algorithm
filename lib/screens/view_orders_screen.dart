import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class ViewOrdersScreen extends StatelessWidget {
  const ViewOrdersScreen({super.key});

  void _showAssignDriverDialog(BuildContext context, OrderModel order) {
    showDialog(
      context: context,
      builder: (context) => AssignDriverDialog(order: order),
    );
  }

  Widget _buildAssignedDrivers(BuildContext context, List<String> driverIds) {
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
              Text('Assigned to: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Loading...'),
            ],
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const Row(
            children: [
              Text('Assigned to: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Error loading drivers'),
            ],
          );
        }

        final drivers = snapshot.data!.where((user) => user != null).cast<UserModel>();
        final driverEmails = drivers.map((d) => d.email ?? 'No Email').join(', ');

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assigned to: ', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(child: Text(driverEmails)),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final user = authProvider.user;
        return Scaffold(
          appBar: AppBar(
            title: const Text('List of Orders'),
          ),
          body: user == null
              ? const Center(child: Text('Please log in to view orders.'))
              : StreamBuilder<List<OrderModel>>(
                  stream: firestoreService.getOrders(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text('No orders found.'));
                    }

                    final orders = snapshot.data!;

                    return ListView.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        final isDenied = order.status == 'denied';

                        return Card(
                          margin: const EdgeInsets.all(8.0),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Order ID: ${order.orderId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Row(
                                      children: [
                                        ElevatedButton(
                                          onPressed: () {
                                            if (isDenied) {
                                              firestoreService.unassignOrder(order.orderId);
                                            } else {
                                              _showAssignDriverDialog(context, order);
                                            }
                                          },
                                          child: Text(isDenied ? 'Reassign' : 'Assign'),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => firestoreService.deleteOrder(order.orderId),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text('Status: ${order.status}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                _buildAssignedDrivers(context, order.driverIds),
                                const SizedBox(height: 8),
                                Text('Pickup: ${order.pickUpAddress.fullAddress}'),
                                const SizedBox(height: 8),
                                const Text('Drop-off(s):', style: TextStyle(fontWeight: FontWeight.bold)),
                                ...order.dropOffAddresses.map((address) => Text(address.fullAddress)),
                                const SizedBox(height: 8),
                                const Divider(),
                                const SizedBox(height: 8),
                                const Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
                                if (order.pickUpAddress.notes != null && order.pickUpAddress.notes!.isNotEmpty)
                                  Text(order.pickUpAddress.notes!),
                                ...order.dropOffAddresses.map((address) {
                                  if (address.notes != null && address.notes!.isNotEmpty) {
                                    return Text(address.notes!);
                                  } else {
                                    return const SizedBox.shrink();
                                  }
                                }),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

class AssignDriverDialog extends StatefulWidget {
  final OrderModel order;

  const AssignDriverDialog({super.key, required this.order});

  @override
  State<AssignDriverDialog> createState() => _AssignDriverDialogState();
}

class _AssignDriverDialogState extends State<AssignDriverDialog> {
  List<String> _selectedDriverIds = [];
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _selectedDriverIds = widget.order.driverIds;
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return AlertDialog(
      title: Text('Assign Drivers to Order ${widget.order.orderId}'),
      content: Container(
        width: 400,
        height: 350,
        child: StreamBuilder<List<UserModel>>(
          stream: firestoreService.getDrivers(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No active drivers found.'));
            }

            final drivers = snapshot.data!;

            return Column(
              children: [
                CheckboxListTile(
                  title: const Text('Select All'),
                  value: _selectAll,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (bool? value) {
                    setState(() {
                      _selectAll = value!;
                      if (_selectAll) {
                        _selectedDriverIds = drivers.map((d) => d.uid).toList();
                      } else {
                        _selectedDriverIds.clear();
                      }
                    });
                  },
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: drivers.length,
                    itemBuilder: (context, index) {
                      final driver = drivers[index];
                      return CheckboxListTile(
                        title: Text(driver.email ?? ''),
                        value: _selectedDriverIds.contains(driver.uid),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (bool? selected) {
                          setState(() {
                            if (selected!) {
                              _selectedDriverIds.add(driver.uid);
                            } else {
                              _selectedDriverIds.remove(driver.uid);
                            }
                            _selectAll = _selectedDriverIds.length == drivers.length;
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            await firestoreService.assignOrderToDrivers(
              widget.order.orderId,
              _selectedDriverIds,
            );
            if (mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
