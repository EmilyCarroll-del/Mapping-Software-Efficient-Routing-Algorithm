import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'inbox.dart'; // Import the InboxPage
import '../services/notification_service.dart';
import '../services/aws_route_service.dart';
import '../models/delivery_address.dart';
import '../providers/delivery_provider.dart';
import '../providers/location_provider.dart';

class MapScreen extends StatefulWidget {
  final DeliveryAddress? deliveryAddress;

  const MapScreen({super.key, this.deliveryAddress});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final AWSRouteService _awsRouteService = AWSRouteService();
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  final User? user = FirebaseAuth.instance.currentUser;

  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(37.42796133580664, -122.085749655962),
    zoom: 14.4746,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final driverId = user?.uid ?? 'driver_ashmini_01';
      NotificationService.instance.initForDriver(driverId);
      Provider.of<DeliveryProvider>(context, listen: false).initialize();

      if (widget.deliveryAddress != null && widget.deliveryAddress!.hasCoordinates) {
        final locationProvider = Provider.of<LocationProvider>(context, listen: false);
        if (locationProvider.isLocationAvailable) {
          _calculateAndDisplayRoute([widget.deliveryAddress!], locationProvider.currentLocation!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location not available, cannot calculate route.')),
          );
        }
      }
    });
    _awsRouteService.initialize();
  }

  Future<void> _calculateAndDisplayRoute(
      List<DeliveryAddress> addresses, LocationData currentLocation) async {
    final startAddress = DeliveryAddress.fromCoordinates(
      latitude: currentLocation.latitude!,
      longitude: currentLocation.longitude!,
    );

    final allAddresses = [startAddress, ...addresses];

    try {
      final routeOptimization = await _awsRouteService.calculateRoute(
        addresses: allAddresses,
        travelMode: 'Car',
      );

      if (routeOptimization.routeGeometry != null) {
        final points = routeOptimization.routeGeometry!
            .map<LatLng>((p) => LatLng(p[0], p[1]))
            .toList();

        final polyline = Polyline(
          polylineId: const PolylineId('aws_route'),
          points: points,
          color: Colors.blue,
          width: 5,
        );

        if (mounted) {
          setState(() {
            _polylines = {polyline};
          });
        }
      }
    } catch (e) {
      print('Error calculating AWS route: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error calculating route: $e')),
        );
      }
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

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (Route<dynamic> route) => false);
    }
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
      body: Consumer2<DeliveryProvider, LocationProvider>(
        builder: (context, deliveryProvider, locationProvider, child) {
          if (deliveryProvider.isLoading || !locationProvider.isLocationAvailable) {
            return const Center(child: CircularProgressIndicator());
          }

          if (widget.deliveryAddress != null && widget.deliveryAddress!.hasCoordinates) {
            _markers = {
              Marker(
                markerId: MarkerId(widget.deliveryAddress!.id),
                position: LatLng(widget.deliveryAddress!.latitude!, widget.deliveryAddress!.longitude!),
                infoWindow: InfoWindow(title: widget.deliveryAddress!.streetAddress, snippet: widget.deliveryAddress!.notes),
              )
            };
          } else {
            _markers = deliveryProvider.addresses.where((a) => a.hasCoordinates).map((address) {
              return Marker(
                markerId: MarkerId(address.id),
                position: LatLng(address.latitude!, address.longitude!),
                infoWindow: InfoWindow(title: address.streetAddress, snippet: address.notes),
              );
            }).toSet();
          }

          _moveCameraToLocation(locationProvider.currentLocation!);

          return GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kGooglePlex,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            polylines: _polylines,
          );
        },
      ),
    );
  }
}
