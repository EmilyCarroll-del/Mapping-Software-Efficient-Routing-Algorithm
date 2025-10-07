import 'package:flutter/material.dart';
import '../models/user_model.dart';

typedef AssignCallback = void Function(List<String> driverIds);

class AssignDriversDialog extends StatefulWidget {
  final List<UserModel> drivers;
  final AssignCallback onAssign;

  const AssignDriversDialog({
    super.key,
    required this.drivers,
    required this.onAssign,
  });

  @override
  _AssignDriversDialogState createState() => _AssignDriversDialogState();
}

class _AssignDriversDialogState extends State<AssignDriversDialog> {
  Set<String> _selectedDriverIds = {};
  bool _isSelectAll = false;

  void _handleDriverSelection(String driverId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedDriverIds.add(driverId);
      } else {
        _selectedDriverIds.remove(driverId);
      }
      _isSelectAll = widget.drivers.isNotEmpty &&
          _selectedDriverIds.length == widget.drivers.length;
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isSelectAll) {
        _selectedDriverIds.clear();
      } else {
        _selectedDriverIds = widget.drivers.map((d) => d.uid).toSet();
      }
      _isSelectAll = !_isSelectAll;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign to Drivers'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.drivers.isNotEmpty)
              CheckboxListTile(
                title: const Text('Select All Drivers'),
                value: _isSelectAll,
                onChanged: (value) => _toggleSelectAll(),
              ),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.drivers.length,
                itemBuilder: (context, index) {
                  final driver = widget.drivers[index];
                  final isSelected = _selectedDriverIds.contains(driver.uid);
                  return CheckboxListTile(
                    title: Text(driver.displayName ?? driver.email ?? driver.uid),
                    value: isSelected,
                    onChanged: (bool? value) {
                      if (value != null) {
                        _handleDriverSelection(driver.uid, value);
                      }
                    },
                  );
                },
              ),
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
          onPressed: _selectedDriverIds.isNotEmpty
              ? () {
                  widget.onAssign(_selectedDriverIds.toList());
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Assign'),
        ),
      ],
    );
  }
}
