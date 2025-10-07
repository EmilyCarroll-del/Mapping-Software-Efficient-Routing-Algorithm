import 'package:flutter/material.dart';
import '../models/delivery_address.dart';
import '../models/user_model.dart';

class AssignAddressDialog extends StatefulWidget {
  final List<UserModel> drivers;
  final List<DeliveryAddress> addresses;
  final Function(String, String) onAssign;

  const AssignAddressDialog({
    super.key,
    required this.drivers,
    required this.addresses,
    required this.onAssign,
  });

  @override
  State<AssignAddressDialog> createState() => _AssignAddressDialogState();
}

class _AssignAddressDialogState extends State<AssignAddressDialog> {
  String? _selectedDriverId;
  String? _selectedAddressId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign Address to Driver'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedDriverId,
            hint: const Text('Select a driver'),
            onChanged: (value) {
              setState(() {
                _selectedDriverId = value;
              });
            },
            items: widget.drivers.map((driver) {
              return DropdownMenuItem(
                value: driver.uid,
                child: Text(driver.displayName ?? driver.email ?? 'N/A'),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedAddressId,
            hint: const Text('Select an address'),
            onChanged: (value) {
              setState(() {
                _selectedAddressId = value;
              });
            },
            items: widget.addresses.where((address) => address.driverId == null).map((address) {
              return DropdownMenuItem(
                value: address.id,
                child: Text(address.fullAddress),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_selectedDriverId != null && _selectedAddressId != null)
              ? () {
                  widget.onAssign(_selectedAddressId!, _selectedDriverId!);
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
