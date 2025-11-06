import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/delivery_address.dart';
import '../services/firestore_service.dart';

// IMPORTANT: When testing on a mobile device, replace 'localhost' with your computer's local IP address.
// Your phone needs to be on the same Wi-Fi network.
// You can find your IP on Windows with 'ipconfig' or on macOS with 'ifconfig'.
const String _apiBaseUrl = kIsWeb ? 'http://localhost:5000' : 'http://YOUR_COMPUTER_IP:5000';

class DriverAssignmentsScreen extends StatefulWidget {
  const DriverAssignmentsScreen({super.key});

  @override
  State<DriverAssignmentsScreen> createState() => _DriverAssignmentsScreenState();
}

class _DriverAssignmentsScreenState extends State<DriverAssignmentsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _notifyAdminOfStatusChange(
      {required String routeId, required String status, required String driverId}) async {
    // For mobile testing, ensure you've replaced 'localhost' with your computer's IP.
    final url = Uri.parse('$_apiBaseUrl/api/notify/route-status');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'routeId': routeId,
          'status': status.toUpperCase(), // Backend expects COMPLETED or DENIED
          'driverId': driverId,
        }),
      );
      if (kDebugMode) {
        print('Admin notification response: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error notifying admin: $e');
      }
    }
  }

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
                          children: _buildActionButtons(address),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  List<Widget> _buildActionButtons(DeliveryAddress address) {
    final status = address.status.toLowerCase();

    // If the delivery is already completed or denied, show no actions.
    if (status == 'completed' || status == 'denied') {
      return []; // Return an empty list of buttons
    }

    // If the delivery is accepted, show 'Complete'.
    if (status == 'accepted') {
      return [
        TextButton(
          onPressed: () {
            _firestoreService.updateDeliveryStatus(address.id, 'completed');
            _notifyAdminOfStatusChange(
              routeId: address.id,
              status: 'completed',
              driverId: currentUser!.uid,
            );
          },
          child: const Text('Complete'),
        ),
      ];
    }

    // Otherwise, show 'Accept' and 'Deny'.
    return [
      TextButton(
        onPressed: () {
          _firestoreService.updateDeliveryStatus(address.id, 'accepted');
          // No notification for 'accepted' status
        },
        child: const Text('Accept'),
      ),
      const SizedBox(width: 8),
      TextButton(
        onPressed: () {
          _firestoreService.updateDeliveryStatus(address.id, 'denied');
          _notifyAdminOfStatusChange(
            routeId: address.id,
            status: 'denied',
            driverId: currentUser!.uid,
          );
        },
        child: const Text('Deny'),
      ),
    ];
  }
}
