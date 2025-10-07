import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UsersList extends StatelessWidget {
  final Stream<List<UserModel>> usersStream;
  final Function(String) onAssignDriver;

  const UsersList({super.key, required this.usersStream, required this.onAssignDriver});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UserModel>>(
      stream: usersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No users found.'));
        }

        final users = snapshot.data!;

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];

            final String displayTitle;
            if (user.displayName != null && user.displayName!.isNotEmpty) {
              displayTitle = user.displayName!;
            } else if (user.email != null && user.email!.contains('@')) {
              displayTitle = user.email!.split('@').first;
            } else {
              displayTitle = user.email ?? 'N/A';
            }

            final role = user.role ?? 'user';
            final capitalizedRole =
                role.isEmpty ? '' : '${role[0].toUpperCase()}${role.substring(1)}';

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
              child: ListTile(
                title: Text(displayTitle),
                subtitle: Text('Role: $capitalizedRole'),
                trailing: user.role != 'driver'
                    ? ElevatedButton(
                        onPressed: () => onAssignDriver(user.uid),
                        child: const Text('Make Driver'),
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}
