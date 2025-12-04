import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:geocoding/geocoding.dart' as geocoding;

import 'inbox.dart'; // Import the InboxPage
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/geocoding_service.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (user != null) {
        NotificationService.instance.initForDriver(user!.uid);
      }
    });
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

    final locationData = await location.getLocation();
    if (mounted) {
      setState(() {
        _currentLocation = locationData;
      });
      // As soon as we have the location, move the camera.
      _moveCameraToLocation(locationData);

      _locationSubscription = location.onLocationChanged.listen((LocationData newLocation) {
        if (mounted) {
          setState(() => _currentLocation = newLocation);
        }
      });
    }
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

  Future<void> _loadAddressMarkers(String userId) async {
    _firestoreService.getDriverDeliveries(userId).listen((addresses) async {
      Set<Marker> newMarkers = {};
      for (var address in addresses) {
        try {
          final geocoded = await GeocodingService.geocodeAddress(address);
          if (geocoded.hasCoordinates) {
            newMarkers.add(
              Marker(
                markerId: MarkerId(address.id),
                position: LatLng(geocoded.latitude!, geocoded.longitude!),
                infoWindow: InfoWindow(title: address.streetAddress, snippet: address.notes),
              ),
            );
          } else {
            print('GeocodingService returned no coordinates for id=${address.id}');
          }
        } catch (e, st) {
          print('GeocodingService error for id=${address.id}: $e\n$st');
        }
      }
      if (mounted) {
        setState(() => _markers = newMarkers);
      }
    });
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    // The GoRouter redirect will handle navigation automatically.
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
              context.push('/driver-assignments');
            },
            icon: const Icon(Icons.assignment, color: Colors.white),
            label: const Text('View Assignments', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.inbox),
            onPressed: () => context.push('/inbox'),
            tooltip: 'Inbox',
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
              initialCameraPosition: CameraPosition(
                target: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                zoom: 14.4746,
              ),
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
