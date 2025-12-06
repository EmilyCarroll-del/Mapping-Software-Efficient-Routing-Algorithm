import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'inbox.dart'; // Import the InboxPage
import '../models/delivery_address.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/profile_service.dart';
import '../widgets/address_list.dart';
import '../widgets/add_edit_address_dialog.dart';
import 'view_drivers_screen.dart';
import 'view_orders_screen.dart';
import 'completed_orders_screen.dart';
import '../services/notification_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ProfileService _profileService = ProfileService();
  User? _initializedUser;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user != null && user != _initializedUser) {
      _initAdminNotifications(user);
      _initializedUser = user;
    } else if (user == null) {
      _initializedUser = null;
    }
  }

  Future<void> _initAdminNotifications(User user) async {
    await NotificationService.instance.initForAdmin(user.uid);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    if (user == null) {
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
            child: FutureBuilder<Map<String, dynamic>?>(
              future: _profileService.getProfile(user.uid, 'admin'),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                  final userData = snapshot.data;
                  final firstName = userData?['first_name'] ?? '';
                  final lastName = userData?['last_name'] ?? '';
                  final userName = userData?['name'] ?? 
                                  (firstName.isNotEmpty || lastName.isNotEmpty
                                      ? '$firstName $lastName'.trim()
                                      : userData?['displayName'] ?? 
                                        user.email?.split('@')[0] ?? 
                                        'User');
                  final companyCode = userData?['companyCode'] as String?;
                  
                  return InkWell(
                    onTap: () => Navigator.of(context).pushNamed('/profile'),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              userName.isNotEmpty ? userName : 'User',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                            if (companyCode != null && companyCode.isNotEmpty) ...[
                              const Text(' • ', style: TextStyle(color: Colors.white70)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  companyCode,
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                          ],
                        ),
                      ),
                    ),
                  );
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
  }

  void _reassignAddress(String addressId) {
    _firestoreService.reassignAddress(addressId);
  }

  Widget _buildTitle(String title) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      color: const Color(0xFF0D2B0D), // Dark green
      child: Center(
        child: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildLoggedInView(BuildContext context, User user) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16.0,
            runSpacing: 8.0,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ViewDriversScreen()),
                  );
                },
                icon: const Icon(Icons.group),
                label: const Text('View Drivers'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/admin-route-history'),
                icon: const Icon(Icons.history),
                label: const Text('Route History'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  backgroundColor: const Color(0xFF2E7D32), // kAdminGreen
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CompletedOrdersScreen()),
                  );
                },
                icon: const Icon(Icons.check_circle),
                label: const Text('Completed Orders'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  backgroundColor: const Color(0xFF2E7D32), // kAdminGreen
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _showAddEditAddressDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add Address'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed('/add-order'),
                icon: const Icon(Icons.add),
                label: const Text('Add Order'),
                style: OutlinedButton.styleFrom(
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
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTitle('List of Addresses'),
                      const SizedBox(height: 8),
                      Expanded(
                        child: AddressList(
                          onEdit: (address) => _showAddEditAddressDialog(address: address),
                          onDelete: _deleteAddress,
                          onReassign: _reassignAddress,
                          addressesStream: _firestoreService.getAddresses(user.uid),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTitle('List of Orders'),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ViewOrdersScreen(showAppBar: false),
                      ),
                    ],
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
