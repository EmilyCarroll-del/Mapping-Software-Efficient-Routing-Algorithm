import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;

  final User? user = FirebaseAuth.instance.currentUser;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    Location location = Location();

    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    _currentLocation = await location.getLocation();
    if (_currentLocation != null) {
      _moveCameraToLocation(_currentLocation!);
    }

    _locationSubscription = location.onLocationChanged.listen((LocationData newLocation) {
      if(mounted) {
        setState(() {
          _currentLocation = newLocation;
        });
         _moveCameraToLocation(newLocation);
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

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Location'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (user?.email != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Text(
                  user!.email!,
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
              ),
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
              markers: {
                if (_currentLocation != null)
                  Marker(
                    markerId: const MarkerId('currentLocation'),
                    position: LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                    infoWindow: const InfoWindow(title: 'My Location'),
                  ),
              },
            ),
    );
  }
}
