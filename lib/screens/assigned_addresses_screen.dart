import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

class AssignedAddressesScreen extends StatelessWidget {
  final FirestoreService _firestoreService = FirestoreService();

  AssignedAddressesScreen({super.key});

  Future<UserModel?> _getDriver(String driverId) async {
    return await _firestoreService.getUserById(driverId);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned Addresses'),
      ),
      body: user == null
          ? const Center(child: Text('Please log in to see your assigned addresses.'))
          : StreamBuilder<List<DeliveryAddress>>(
              stream: _firestoreService.getAssignedAddresses(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No addresses have been assigned yet.'));
                }

                final assignedAddresses = snapshot.data!;

                return ListView.builder(
                  itemCount: assignedAddresses.length,
                  itemBuilder: (context, index) {
                    final address = assignedAddresses[index];
                    if (address.driverId == null) {
                      return Card(
                        margin: const EdgeInsets.all(8.0),
                        child: ListTile(
                          title: Text(address.fullAddress),
                          subtitle: const Text('Error: Driver ID is missing.'),
                        ),
                      );
                    }
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        title: Text(address.fullAddress),
                        subtitle: FutureBuilder<UserModel?>(
                          future: _getDriver(address.driverId!),
                          builder: (context, driverSnapshot) {
                            if (driverSnapshot.connectionState == ConnectionState.waiting) {
                              return const Text('Loading driver...');
                            }
                            if (driverSnapshot.hasError || driverSnapshot.data == null) {
                              return const Text('Driver not found');
                            }
                            final driver = driverSnapshot.data!;
                            final capitalizedStatus = address.status.isEmpty
                                ? ''
                                : '${address.status[0].toUpperCase()}${address.status.substring(1)}';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Assigned to: ${driver.displayName ?? driver.email ?? 'Unknown Driver'}'),
                                Text('Status: $capitalizedStatus'),
                              ],
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
