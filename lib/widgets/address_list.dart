import 'package:flutter/material.dart';
import '../models/delivery_address.dart';

typedef SelectionChangedCallback = void Function(Set<String> selectedIds);

class AddressList extends StatefulWidget {
  final Stream<List<DeliveryAddress>> addressesStream;
  final Function(DeliveryAddress) onEdit;
  final Function(String) onDelete;
  final Function(String) onReassign;
  final SelectionChangedCallback onSelectionChanged;
  final bool isReadOnly;
  final bool showSectionHeaders;

  const AddressList({
    super.key,
    required this.addressesStream,
    required this.onEdit,
    required this.onDelete,
    required this.onReassign,
    required this.onSelectionChanged,
    this.isReadOnly = false,
    this.showSectionHeaders = true,
  });

  @override
  AddressListState createState() => AddressListState();
}

class AddressListState extends State<AddressList> {
  Set<String> _selectedAddressIds = {};
  List<DeliveryAddress> _availableAddresses = [];
  bool _isSelectAll = false;

  void clearSelection() {
    setState(() {
      _selectedAddressIds.clear();
      _isSelectAll = false;
    });
  }

  void _handleAddressSelection(String addressId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedAddressIds.add(addressId);
      } else {
        _selectedAddressIds.remove(addressId);
      }
      _isSelectAll = _availableAddresses.isNotEmpty &&
          _selectedAddressIds.length == _availableAddresses.length;
    });
    widget.onSelectionChanged(_selectedAddressIds);
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isSelectAll) {
        _selectedAddressIds.clear();
        _isSelectAll = false;
      } else {
        _selectedAddressIds = _availableAddresses.map((addr) => addr.id).toSet();
        _isSelectAll = true;
      }
    });
    widget.onSelectionChanged(_selectedAddressIds);
  }

  Widget _buildAddressTile(DeliveryAddress address, {bool isSelectable = true}) {
    final isSelected = _selectedAddressIds.contains(address.id);
    final capitalizedStatus = address.status.isEmpty
        ? ''
        : '${address.status[0].toUpperCase()}${address.status.substring(1)}'.replaceAll('_', ' ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
      child: ListTile(
        leading: widget.isReadOnly || !isSelectable
            ? null
            : Checkbox(
                value: isSelected,
                onChanged: (bool? value) {
                  if (value != null) {
                    _handleAddressSelection(address.id, value);
                  }
                },
              ),
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
                  if (address.status != 'reserved') ...[
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
        final reservedAddresses = allAddresses.where((a) => a.status == 'reserved').toList();
        _availableAddresses = allAddresses.where((a) => a.status != 'reserved').toList();

        final availableIds = _availableAddresses.map((e) => e.id).toSet();
        _selectedAddressIds.removeWhere((id) => !availableIds.contains(id));

        return CustomScrollView(
          slivers: [
            if (_availableAddresses.isNotEmpty && !widget.isReadOnly)
              SliverToBoxAdapter(
                child: Padding(
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
              ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final address = _availableAddresses[index];
                  return _buildAddressTile(address, isSelectable: true);
                },
                childCount: _availableAddresses.length,
              ),
            ),
            if (widget.showSectionHeaders && reservedAddresses.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text('Included in Orders', style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
            ],
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final address = reservedAddresses[index];
                  return _buildAddressTile(address, isSelectable: false);
                },
                childCount: reservedAddresses.length,
              ),
            ),
          ],
        );
      },
    );
  }
}
