import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/delivery_address.dart';
import '../services/address_validation_service.dart';

class AddEditAddressDialog extends StatefulWidget {
  final DeliveryAddress? address;
  final String userId;
  final Function(DeliveryAddress) onSave;

  const AddEditAddressDialog({
    super.key,
    this.address,
    required this.userId,
    required this.onSave,
  });

  @override
  State<AddEditAddressDialog> createState() => _AddEditAddressDialogState();
}

class _AddEditAddressDialogState extends State<AddEditAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _addressController;
  late TextEditingController _notesController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: widget.address?.fullAddress ?? '');
    _notesController = TextEditingController(text: widget.address?.notes ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.address != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Address' : 'Add Address'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Enter Address',
                  hintText: 'Street, City, State, ZIP Code',
                ),
                validator: (value) => value!.isEmpty ? 'Please enter an address' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'Notes (Optional)'),
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final validationResult = await AddressValidationService.validateAddress(_addressController.text);
        final result = validationResult['result']?['address']?['postalAddress'];
        final verdict = validationResult['result']?['verdict'];

        // Accept the address if the API considers it \"complete\".
        // This is a better signal for validation than checking for unconfirmed components.
        if (result != null && verdict != null && verdict['addressComplete'] == true) {
          final newAddress = DeliveryAddress(
            id: widget.address?.id,
            userId: widget.userId,
            streetAddress: result['addressLines'][0] ?? '',
            city: result['locality'] ?? '',
            state: result['administrativeArea'] ?? '',
            zipCode: result['postalCode'] ?? '',
            notes: _notesController.text,
          );

          widget.onSave(newAddress);
          Navigator.of(context).pop();
        } else {
          // Provide a more detailed error message
          String errorMessage = 'Invalid address. Please try again.';
          if (verdict != null) {
            final issues = <String>[];
            if (verdict['addressComplete'] != true) {
              issues.add("The address appears to be incomplete.");
            }
            if (verdict['hasUnconfirmedComponents'] == true) {
              issues.add("Some address components could not be confirmed.");
            }
             errorMessage = issues.isNotEmpty ? issues.join(' ') : errorMessage;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to validate address: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
