import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/delivery_address.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';

class AddOrderScreen extends StatefulWidget {
  const AddOrderScreen({super.key});

  @override
  State<AddOrderScreen> createState() => _AddOrderScreenState();
}

class _AddOrderScreenState extends State<AddOrderScreen> {
  final TextEditingController _pickUpSearchController = TextEditingController();
  final TextEditingController _dropOffSearchController = TextEditingController();
  final _orderIdController = TextEditingController();

  DeliveryAddress? _selectedPickUpAddress;
  String? _selectedPickUpAddressId;
  final List<DeliveryAddress> _selectedDropOffAddresses = [];

  String _pickUpSearchQuery = '';
  String _dropOffSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _generateUniqueOrderId();
    _pickUpSearchController.addListener(() {
      setState(() {
        _pickUpSearchQuery = _pickUpSearchController.text;
      });
    });
    _dropOffSearchController.addListener(() {
      setState(() {
        _dropOffSearchQuery = _dropOffSearchController.text;
      });
    });
  }

  Future<void> _generateUniqueOrderId() async {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final random = Random();
    String orderId;
    do {
      orderId = (1000 + random.nextInt(9000)).toString();
    } while (await firestoreService.orderIdExists(orderId));
    if (mounted) {
      _orderIdController.text = orderId;
    }
  }

  @override
  void dispose() {
    _pickUpSearchController.dispose();
    _dropOffSearchController.dispose();
    _orderIdController.dispose();
    super.dispose();
  }

  void _showConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Order'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order ID: ${_orderIdController.text}'),
              const SizedBox(height: 16),
              const Text('Pick Up:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_selectedPickUpAddress!.fullAddress),
              const SizedBox(height: 16),
              const Text('Drop Off(s):', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._selectedDropOffAddresses.map((address) => Text('- ${address.fullAddress}')),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final firestoreService = Provider.of<FirestoreService>(context, listen: false);
                final adminId = Provider.of<AuthProvider>(context, listen: false).user!.uid;

                await firestoreService.createOrder(
                  orderId: _orderIdController.text,
                  adminId: adminId,
                  pickUpAddress: _selectedPickUpAddress!,
                  dropOffAddresses: _selectedDropOffAddresses,
                );
                if (mounted) {
                  Navigator.of(context).pop(); // Close the dialog
                  Navigator.of(context).pop(); // Go back to the previous screen
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final user = Provider.of<AuthProvider>(context, listen: false).user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Order'),
      ),
      body: user == null
          ? const Center(child: Text('Please log in to add an order.'))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select Pick Up Address', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pickUpSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Pick Up Addresses',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<DeliveryAddress>>(
                      stream: firestoreService.getUnassignedAddresses(user.uid),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        var addresses = snapshot.data!;
                        final originalAddresses = snapshot.data!;

                        if (_pickUpSearchQuery.isNotEmpty) {
                          addresses = addresses.where((address) => address.fullAddress.toLowerCase().contains(_pickUpSearchQuery.toLowerCase())).toList();
                        }

                        return ListView.builder(
                          itemCount: addresses.length,
                          itemBuilder: (context, index) {
                            final address = addresses[index];
                            return RadioListTile<String>(
                              title: Text(address.fullAddress),
                              value: address.id,
                              groupValue: _selectedPickUpAddressId,
                              activeColor: Colors.deepPurple,
                              onChanged: (String? selectedId) {
                                setState(() {
                                  _selectedPickUpAddressId = selectedId;
                                  if (selectedId == null) {
                                    _selectedPickUpAddress = null;
                                  } else {
                                    _selectedPickUpAddress = originalAddresses.firstWhere((addr) => addr.id == selectedId);
                                  }
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Select Drop Off Address(es)', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _dropOffSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Search Drop Off Addresses',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<DeliveryAddress>>(
                      stream: firestoreService.getUnassignedAddresses(user.uid),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        var addresses = snapshot.data!;

                        if (_selectedPickUpAddress != null) {
                          addresses = addresses.where((address) => address.id != _selectedPickUpAddress!.id).toList();
                        }

                        if (_dropOffSearchQuery.isNotEmpty) {
                          addresses = addresses.where((address) => address.fullAddress.toLowerCase().contains(_dropOffSearchQuery.toLowerCase())).toList();
                        }

                        return ListView.builder(
                          itemCount: addresses.length,
                          itemBuilder: (context, index) {
                            final address = addresses[index];
                            return CheckboxListTile(
                              title: Text(address.fullAddress),
                              value: _selectedDropOffAddresses.any((a) => a.id == address.id),
                              onChanged: (selected) {
                                setState(() {
                                  if (selected!) {
                                    _selectedDropOffAddresses.add(address);
                                  } else {
                                    _selectedDropOffAddresses.removeWhere((a) => a.id == address.id);
                                  }
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ElevatedButton(
          onPressed: () {
            if (_selectedPickUpAddress != null && _selectedDropOffAddresses.isNotEmpty) {
              _showConfirmationDialog();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please select a pickup address and at least one drop-off address.')),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Create Order'),
        ),
      ),
    );
  }
}
