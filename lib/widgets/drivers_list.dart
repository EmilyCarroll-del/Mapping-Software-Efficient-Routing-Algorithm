import 'package:flutter/material.dart';
import '../models/user_model.dart';

class DriversList extends StatelessWidget {
  final Stream<List<UserModel>> driversStream;
  final Function(String) onRemoveDriver;

  const DriversList({
    super.key,
    required this.driversStream,
    required this.onRemoveDriver,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: driversStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No drivers found.'));
        }

        final drivers = snapshot.data!;

        return ListView.builder(
          itemCount: drivers.length,
          itemBuilder: (context, index) {
            final driver = drivers[index];

            final String displayTitle = driver.email?.split('@').first ?? 'N/A';

            final role = driver.role ?? 'driver';
            final capitalizedRole =
                role.isEmpty ? '' : '${role[0].toUpperCase()}${role.substring(1)}';

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
              child: ListTile(
                title: Text(displayTitle),
                subtitle: Text('Role: $capitalizedRole'),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                  tooltip: 'Remove Driver Role',
                  onPressed: () => onRemoveDriver(driver.uid),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
