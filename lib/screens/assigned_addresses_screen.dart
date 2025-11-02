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
      ),
      body: user == null
          ? const Center(child: Text('Please log in to see assigned addresses.'))
          : AddressList(
              addressesStream: firestoreService.getAssignedAddresses(user.uid),
              onEdit: (address) {},
              onDelete: (addressId) {},
              onReassign: (addressId) {},
              onSelectionChanged: (selectedIds) {},
              isReadOnly: true,
              showSectionHeaders: false,
            ),
    );
  }
}
