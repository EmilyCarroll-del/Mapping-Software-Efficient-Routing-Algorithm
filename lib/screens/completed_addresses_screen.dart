import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../widgets/address_list.dart';

class CompletedAddressesScreen extends StatelessWidget {
  const CompletedAddressesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Completed Addresses'),
      ),
      body: user == null
          ? const Center(child: Text('Please log in to see completed addresses.'))
          : AddressList(
              addressesStream: firestoreService.getCompletedAddressesForAdmin(user.uid),
              isReadOnly: true,
              onEdit: (address) {},
              onDelete: (addressId) {},
              onReassign: (addressId) {},
              onSelectionChanged: (selectedIds) {},
            ),
    );
  }
}
