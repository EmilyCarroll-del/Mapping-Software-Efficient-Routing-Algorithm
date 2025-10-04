import 'package:flutter/material.dart';
import '../models/delivery_address.dart';

class AddressList extends StatelessWidget {
  final Stream<List<DeliveryAddress>> addressesStream;
  final Function(DeliveryAddress) onEdit;
  final Function(String) onDelete;

  const AddressList({
    super.key,
    required this.addressesStream,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryAddress>>(
      stream: addressesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No addresses found.'));
        }

        final addresses = snapshot.data!;

        return ListView.builder(
          itemCount: addresses.length,
          itemBuilder: (context, index) {
            final address = addresses[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(address.fullAddress),
                subtitle: const Text('Status: Pending'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => onEdit(address),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => onDelete(address.id),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
