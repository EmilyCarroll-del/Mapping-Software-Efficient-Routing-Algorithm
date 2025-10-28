import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

import 'inbox.dart'; // Import the InboxPage
import '../models/delivery_address.dart';
import '../services/firestore_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final FirestoreService _firestoreService = FirestoreService();
  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;
  Set<Marker> _markers = {};

  final User? user = FirebaseAuth.instance.currentUser;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  @override
  void initState() {
    super.initState();
    _initializeLocationAndMarkers();
  }

  Future<void> _initializeLocationAndMarkers() async {
    await _initializeLocation();
    if (user != null) {
      _loadAddressMarkers(user!.uid);
    }
  }

  Future<void> _initializeLocation() async {
    Location location = Location();
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    _currentLocation = await location.getLocation();
    if (_currentLocation != null) {
      _moveCameraToLocation(_currentLocation!);
    }

    _locationSubscription = location.onLocationChanged.listen((LocationData newLocation) {
      if (mounted) {
        setState(() => _currentLocation = newLocation);
        _moveCameraToLocation(newLocation);
      }
    });
  }

  Future<void> _loadAddressMarkers(String userId) async {
    _firestoreService.getDriverDeliveries(userId).listen((addresses) async {
      Set<Marker> newMarkers = {};
      for (var address in addresses) {
        if (address.streetAddress.isNotEmpty &&
            address.city.isNotEmpty &&
            address.state.isNotEmpty &&
            address.zipCode.isNotEmpty) {
          try {
            List<geocoding.Location> locations = await geocoding.locationFromAddress(
              '${address.streetAddress}, ${address.city}, ${address.state} ${address.zipCode}'
            );
            if (locations.isNotEmpty) {
              final loc = locations.first;
              newMarkers.add(
                Marker(
                  markerId: MarkerId(address.id),
                  position: LatLng(loc.latitude, loc.longitude),
                  infoWindow: InfoWindow(title: address.streetAddress, snippet: address.notes),
                ),
              );
            }
          } catch (e) {
            print("Error geocoding address: ${e}");
          }
        }
      }
      if (mounted) {
        setState(() => _markers = newMarkers);
      }
    });
  }

  Future<void> _moveCameraToLocation(LocationData locationData) async {
    final GoogleMapController controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(locationData.latitude!, locationData.longitude!),
        zoom: 15.0,
      ),
    ));
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("GraphGo Driver"),
        automaticallyImplyLeading: false,
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pushNamed('/driver-assignments');
            },
            icon: const Icon(Icons.assignment, color: Colors.white),
            label: const Text('View Assignments', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.inbox),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const InboxPage()),
              );
            },
            tooltip: 'Inbox',
          ),
          if (user?.email != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(child: Text(user!.email!, style: const TextStyle(fontSize: 12))),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: _kGooglePlex,
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,

              markers: _markers,
            ),
    );
  }
}
