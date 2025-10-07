import 'package:flutter/material.dart';
import '../models/delivery_address.dart';

class SelectAddressDialog extends StatefulWidget {
  final List<DeliveryAddress> addresses;
  final Function(List<String>) onSelect;

  const SelectAddressDialog({
    super.key,
    required this.addresses,
    required this.onSelect,
  });

  @override
  State<SelectAddressDialog> createState() => _SelectAddressDialogState();
}

class _SelectAddressDialogState extends State<SelectAddressDialog> {
  final List<String> _selectedAddressIds = [];

  void _addAddress() {
    setState(() {
      _selectedAddressIds.add("");
    });
  }

  @override
  Widget build(BuildContext context) {
    final unassignedAddresses = widget.addresses.where((a) => a.driverId == null).toList();

    return AlertDialog(
      title: const Text('Select Addresses'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._selectedAddressIds.asMap().entries.map((entry) {
              int index = entry.key;
              return DropdownButtonFormField<String>(
                value: _selectedAddressIds[index].isEmpty ? null : _selectedAddressIds[index],
                hint: const Text('Choose an address'),
                onChanged: (value) {
                  setState(() {
                    _selectedAddressIds[index] = value!;
                  });
                },
                items: unassignedAddresses.map((address) {
                  return DropdownMenuItem(
                    value: address.id,
                    child: Text(address.fullAddress, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
              );
            }).toList(),
            const SizedBox(height: 16),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addAddress,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedAddressIds.isNotEmpty && _selectedAddressIds.every((id) => id.isNotEmpty)
              ? () {
                  widget.onSelect(_selectedAddressIds);
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
