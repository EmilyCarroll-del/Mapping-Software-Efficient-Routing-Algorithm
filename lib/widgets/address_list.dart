import 'package:flutter/material.dart';
import '../models/delivery_address.dart';

typedef SelectionChangedCallback = void Function(Set<String> selectedIds);

class AddressList extends StatefulWidget {
  final Stream<List<DeliveryAddress>> addressesStream;
  final Function(DeliveryAddress) onEdit;
  final Function(String) onDelete;
  final Function(String) onReassign;
  final SelectionChangedCallback onSelectionChanged;

  const AddressList({
    super.key,
    required this.addressesStream,
    required this.onEdit,
    required this.onDelete,
    required this.onReassign,
    required this.onSelectionChanged,
  });

  @override
  _AddressListState createState() => _AddressListState();
}

class _AddressListState extends State<AddressList> {
  Set<String> _selectedAddressIds = {};
  List<DeliveryAddress> _currentAddresses = [];
  bool _isSelectAll = false;

  void _handleAddressSelection(String addressId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedAddressIds.add(addressId);
      } else {
        _selectedAddressIds.remove(addressId);
      }
      _isSelectAll = _currentAddresses.isNotEmpty &&
          _selectedAddressIds.length == _currentAddresses.length;
    });
    widget.onSelectionChanged(_selectedAddressIds);
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isSelectAll) {
        _selectedAddressIds.clear();
        _isSelectAll = false;
      } else {
        _selectedAddressIds = _currentAddresses.map((addr) => addr.id).toSet();
        _isSelectAll = true;
      }
    });
    widget.onSelectionChanged(_selectedAddressIds);
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

        _currentAddresses = snapshot.data!;
        final currentIds = _currentAddresses.map((e) => e.id).toSet();
        _selectedAddressIds.removeWhere((id) => !currentIds.contains(id));

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                children: [
                  Checkbox(
                    value: _isSelectAll,
                    onChanged: (bool? value) {
                      _toggleSelectAll();
                    },
                  ),
                  const Text('Select All'),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _currentAddresses.length,
                itemBuilder: (context, index) {
                  final address = _currentAddresses[index];
                  final isSelected = _selectedAddressIds.contains(address.id);
                  final capitalizedStatus = address.status.isEmpty
                      ? ''
                      : '${address.status[0].toUpperCase()}${address.status.substring(1)}';

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
                    child: ListTile(
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (bool? value) {
                          if (value != null) {
                            _handleAddressSelection(address.id, value);
                          }
                        },
                      ),
                      title: Text(address.fullAddress),
                      subtitle: Text('Status: $capitalizedStatus'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (address.status == 'denied')
                            TextButton(
                              onPressed: () => widget.onReassign(address.id),
                              child: const Text('Reassign', style: TextStyle(color: Colors.orange)),
                            ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            onPressed: () => widget.onEdit(address),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => widget.onDelete(address.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
