import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../providers/auth_provider.dart';
import 'inbox.dart'; // Import the InboxPage
import '../models/delivery_address.dart';
import '../services/firestore_service.dart';
import '../widgets/address_list.dart';
import '../widgets/add_edit_address_dialog.dart';
import '../widgets/assign_drivers_dialog.dart';
import '../widgets/drivers_list.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  Set<String> _selectedAddressIds = {};

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    if (user == null) {
      // While the user is null, the AuthProvider is still determining the auth state.
      // Show a loading indicator until the user is fetched.
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: () => Navigator.of(context).pushNamed('/settings'),
        ),
        title: const Text('GraphGo Admin', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.inbox, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InboxPage()),
              );
            },
            tooltip: 'Inbox',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  return Center(child: Text(snapshot.data!['name'] ?? '', style: const TextStyle(color: Colors.white)));
                }
                return const Center(child: Text('', style: TextStyle(color: Colors.white)));
              },
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              authProvider.signOut();
            },
            icon: const Icon(Icons.logout, color: Colors.white, size: 18),
          ),
        ],
      ),
      body: _buildLoggedInView(context, user),
    );
  }

  void _onSelectionChanged(Set<String> selectedIds) {
    setState(() {
      _selectedAddressIds = selectedIds;
    });
  }

  void _showAddEditAddressDialog({DeliveryAddress? address}) {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;
    showDialog(
      context: context,
      builder: (context) => AddEditAddressDialog(
        address: address,
        userId: user.uid,
        onSave: (address) {
          _firestoreService.saveAddress(address);
        },
      ),
    );
  }

  Future<void> _showUploadCsvDialog() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || !mounted) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      final content = utf8.decode(bytes);
      final list = const CsvToListConverter().convert(content);

      if (list.isNotEmpty) {
        list.removeAt(0);
      }

      final addresses = list
          .map((row) {
            try {
              return DeliveryAddress(
                userId: user.uid,
                streetAddress: row[0].toString(),
                city: row[1].toString(),
                state: row[2].toString(),
                zipCode: row[3].toString(),
                notes: row.length > 4 ? row[4].toString() : null,
              );
            } catch (e) {
              print('Error parsing row: $row, error: $e');
              return null;
            }
          })
          .where((address) => address != null)
          .cast<DeliveryAddress>()
          .toList();

      if (!mounted) return;

      if (addresses.isNotEmpty) {
        try {
          await _firestoreService.saveAddressesFromCsv(addresses);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Addresses uploaded successfully!')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error uploading addresses: $e')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No valid addresses found in the CSV file.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  void _deleteAddress(String addressId) {
    _firestoreService.deleteAddress(addressId);
    setState(() {
      _selectedAddressIds.remove(addressId);
    });
  }

  void _reassignAddress(String addressId) {
    _firestoreService.reassignAddress(addressId);
  }

  void _removeDriverRole(String uid) {
    _firestoreService.removeDriverRole(uid);
  }

  void _showAssignDriversDialog() async {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null || _selectedAddressIds.isEmpty) return;

    final drivers = await _firestoreService.getDrivers().first;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AssignDriversDialog(
        drivers: drivers,
        onAssign: (selectedDriverIds) {
          _firestoreService.assignAddressesToDrivers(
            _selectedAddressIds.toList(),
            selectedDriverIds,
          );
          setState(() {
            _selectedAddressIds.clear();
          });
        },
      ),
    );
  }

  Widget _buildLoggedInView(BuildContext context, User user) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            flex: 3, // 75% of the space
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16.0,
                  runSpacing: 8.0,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showAddEditAddressDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Address'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showUploadCsvDialog,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload CSV'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pushNamed('/assigned-addresses'),
                      icon: const Icon(Icons.assignment_turned_in),
                      label: const Text('View Assigned Addresses'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    if (_selectedAddressIds.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: _showAssignDriversDialog,
                        icon: const Icon(Icons.assignment_ind),
                        label: Text('Assign Selected (${_selectedAddressIds.length})'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'List of Addresses',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Expanded(
                  child: AddressList(
                    onEdit: (address) => _showAddEditAddressDialog(address: address),
                    onDelete: _deleteAddress,
                    onReassign: _reassignAddress,
                    addressesStream: _firestoreService.getAddresses(user.uid),
                    onSelectionChanged: _onSelectionChanged,
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 32),
          Expanded(
            flex: 1, // 25% of the space
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Drivers', style: Theme.of(context).textTheme.headlineSmall),
                Expanded(
                  child: DriversList(
                    driversStream: _firestoreService.getDrivers(),
                    onRemoveDriver: _removeDriverRole,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
