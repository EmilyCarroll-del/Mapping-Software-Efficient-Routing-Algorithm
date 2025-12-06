import 'package:flutter/material.dart';
import '../models/delivery_address.dart';

class AddressList extends StatefulWidget {
  final Stream<List<DeliveryAddress>> addressesStream;
  final Function(DeliveryAddress) onEdit;
  final Function(String) onDelete;
  final Function(String) onReassign;
  final bool isReadOnly;

  const AddressList({
    super.key,
    required this.addressesStream,
    required this.onEdit,
    required this.onDelete,
    required this.onReassign,
    this.isReadOnly = false,
  });

  @override
  AddressListState createState() => AddressListState();
}

class AddressListState extends State<AddressList> {

  void clearSelection() {
  }

  Widget _buildAddressTile(DeliveryAddress address) {
    final capitalizedStatus = address.status.isEmpty
        ? ''
        : '${address.status[0].toUpperCase()}${address.status.substring(1)}'.replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
      child: ListTile(
        title: Text(address.fullAddress),
        subtitle: Text('Status: $capitalizedStatus'),
        trailing: widget.isReadOnly
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (address.status == 'denied')
                    TextButton(
                      onPressed: () => widget.onReassign(address.id),
                      child: const Text('Reassign', style: TextStyle(color: Colors.orange)),
                    ),
                  if (address.status != 'reserved' && address.status != 'in_progress') ...[
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () => widget.onEdit(address),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => widget.onDelete(address.id),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryAddress>>(
      stream: widget.addressesStream,
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

        final allAddresses = snapshot.data!;
        // We only want to show addresses that are not part of an order yet
        final availableAddresses = allAddresses.where((a) => a.status != 'reserved').toList();

        if (availableAddresses.isEmpty) {
          return const Center(child: Text('No available addresses to display.'));
        }

        return ListView.builder(
          itemCount: availableAddresses.length,
          itemBuilder: (context, index) {
            final address = availableAddresses[index];
            return _buildAddressTile(address);
          },
        );
      },
    );
  }
}
