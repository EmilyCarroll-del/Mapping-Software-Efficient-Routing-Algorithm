import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/aws_route_service.dart';
import '../models/delivery_address.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  final AWSRouteService _routeService = AWSRouteService();
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  final DeliveryAddress _startAddress = DeliveryAddress(
    streetAddress: '1 Infinite Loop',
    city: 'Cupertino',
    state: 'CA',
    zipCode: '95014',
    latitude: 37.3318,
    longitude: -122.0312,
  );

  final DeliveryAddress _endAddress = DeliveryAddress(
    streetAddress: '1600 Amphitheatre Parkway',
    city: 'Mountain View',
    state: 'CA',
    zipCode: '94043',
    latitude: 37.4220,
    longitude: -122.0841,
  );

  @override
  void initState() {
    super.initState();
    _addMarkers();
    _routeService.initialize();
  }

  void _addMarkers() {
    _markers.add(Marker(
      markerId: const MarkerId('start'),
      position: LatLng(_startAddress.latitude!, _startAddress.longitude!),
      infoWindow: const InfoWindow(title: 'Start'),
    ));
    _markers.add(Marker(
      markerId: const MarkerId('end'),
      position: LatLng(_endAddress.latitude!, _endAddress.longitude!),
      infoWindow: const InfoWindow(title: 'End'),
    ));
  }

  Future<void> _calculateAndDisplayRoute() async {
    try {
      final routeData = await _routeService.calculateRoute(
        addresses: [_startAddress, _endAddress],
        travelMode: 'Truck',
      );

      if (routeData.routeGeometry != null) {
        final List<LatLng> routePoints = routeData.routeGeometry!
            .map((point) => LatLng(point[0], point[1]))
            .toList();

        setState(() {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: routePoints,
              color: Colors.blue,
              width: 5,
            ),
          );
        });

        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            _createLatLngBounds(routePoints),
            50.0, // padding
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating route: $e')),
      );
    }
  }

  LatLngBounds _createLatLngBounds(List<LatLng> points) {
    final southwest = points.reduce((a, b) => LatLng(
          a.latitude < b.latitude ? a.latitude : b.latitude,
          a.longitude < b.longitude ? a.longitude : b.longitude,
        ));
    final northeast = points.reduce((a, b) => LatLng(
          a.latitude > b.latitude ? a.latitude : b.latitude,
          a.longitude > b.longitude ? a.longitude : b.longitude,
        ));
    return LatLngBounds(southwest: southwest, northeast: northeast);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AWS Truck Route'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(_startAddress.latitude!, _startAddress.longitude!),
          zoom: 12,
        ),
        onMapCreated: (controller) => _mapController = controller,
        markers: _markers,
        polylines: _polylines,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _calculateAndDisplayRoute,
        tooltip: 'Calculate Route',
        child: const Icon(Icons.directions),
      ),
    );
  }
}
