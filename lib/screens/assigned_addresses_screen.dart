import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/address_list.dart';

class AssignedAddressesScreen extends StatelessWidget {
  const AssignedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned Addresses'),
        backgroundColor: const Color(0xFF0D2B0D), // Matching admin theme
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('Please log in to see assigned addresses.'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200), // Max width for readability
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: AddressList(
                        addressesStream: firestoreService.getAssignedAddresses(user.uid),
                        onEdit: (address) {},
                        onDelete: (addressId) {},
                        onReassign: (addressId) {},
                        onSelectionChanged: (selectedIds) {},
                        isReadOnly: true,
                        showSectionHeaders: true, // Group by status
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
