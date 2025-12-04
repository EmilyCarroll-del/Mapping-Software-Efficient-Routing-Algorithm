import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

import '../models/delivery_address.dart';
import '../services/firestore_service.dart';
import '../services/aws_route_service.dart';

class DriverAssignmentsScreen extends StatefulWidget {
  const DriverAssignmentsScreen({super.key});

  @override
  State<DriverAssignmentsScreen> createState() => _DriverAssignmentsScreenState();
}

class _DriverAssignmentsScreenState extends State<DriverAssignmentsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final AWSRouteService _awsRouteService = AWSRouteService();
  final User? currentUser = FirebaseAuth.instance.currentUser;
  bool _isCalculating = false;

  Future<void> _calculateAndNavigate(DeliveryAddress destination) async {
    setState(() {
      _isCalculating = true;
    });

    try {
      // 1. Get driver's current location
      final location = Location();
      final hasPermission = await location.requestPermission();
      if (hasPermission != PermissionStatus.granted) {
        throw Exception('Location permission denied.');
      }
      final currentLocation = await location.getLocation();
      // CORRECTED: Use the correct constructor for DeliveryAddress
      final startAddress = DeliveryAddress(
        userId: currentUser?.uid ?? '',
        streetAddress: 'Current Location',
        city: '',
        state: '',
        zipCode: '',
        latitude: currentLocation.latitude!,
        longitude: currentLocation.longitude!,
      );

      // 2. Calculate the route
      final route = await _awsRouteService.calculateRoute(
        addresses: [startAddress, destination],
        travelMode: 'Truck', // or 'Car'
      );

      // TODO: Navigate to a map screen to display the route
      print('Successfully calculated route!');
      print('Total distance: ${route.totalDistance} km');
      print('Estimated time: ${route.estimatedTime?.inMinutes} minutes');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Route calculated! Distance: ${route.totalDistance?.toStringAsFixed(2)} km.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating route: $e')),
      );
    } finally {
      setState(() {
        _isCalculating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Assignments'),
      ),
      body: Stack(
        children: [
          currentUser == null
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
                                IconButton(
                                  icon: const Icon(Icons.navigation, color: Colors.deepPurple),
                                  tooltip: 'Navigate',
                                  onPressed: () => _calculateAndNavigate(address),
                                ),
                                const SizedBox(width: 8),
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
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
          if (_isCalculating)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Calculating Route...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
