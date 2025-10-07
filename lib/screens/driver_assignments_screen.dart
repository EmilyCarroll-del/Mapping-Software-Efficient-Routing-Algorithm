import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/delivery_address.dart';
import '../services/firestore_service.dart';

class DriverAssignmentsScreen extends StatefulWidget {
  const DriverAssignmentsScreen({super.key});

  @override
  State<DriverAssignmentsScreen> createState() => _DriverAssignmentsScreenState();
}

class _DriverAssignmentsScreenState extends State<DriverAssignmentsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assignments'),
      ),
      body: currentUser == null
          ? const Center(child: Text('Please log in to see your assignments.'))
          : StreamBuilder<List<DeliveryAddress>>(
              stream: _firestoreService.getDriverDeliveries(currentUser!.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No Assignments Yet'));
                }

                final addresses = snapshot.data!;

                return ListView.builder(
                  itemCount: addresses.length,
                  itemBuilder: (context, index) {
                    final address = addresses[index];
                    final capitalizedStatus = address.status.isEmpty
                        ? ''
                        : '${address.status[0].toUpperCase()}${address.status.substring(1)}';
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      child: ListTile(
                        title: Text(address.fullAddress),
                        subtitle: Text('Status: $capitalizedStatus'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                _firestoreService.updateDeliveryStatus(address.id, 'accepted');
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepPurple,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                _firestoreService.denyAssignment(address.id);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade700,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Deny'),
                            ),
                          ],
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
