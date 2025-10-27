import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:collection';

import '../models/delivery_address.dart';
import '../providers/delivery_provider.dart';
import '../services/routing_algorithms.dart';

class OptimizedRouteMapScreen extends StatefulWidget {
  final List<DeliveryAddress> selectedOrders;

  const OptimizedRouteMapScreen({super.key, required this.selectedOrders});

  @override
  State<OptimizedRouteMapScreen> createState() => _OptimizedRouteMapScreenState();
}

class _OptimizedRouteMapScreenState extends State<OptimizedRouteMapScreen> {
  late GoogleMapController _mapController;
  final Set<Marker> _markers = HashSet<Marker>();
  final Set<Polyline> _polylines = HashSet<Polyline>();
  List<DeliveryAddress> _optimizedRoute = [];

  @override
  void initState() {
    super.initState();
    _createMarkers();
  }

  void _createMarkers() {
    for (var order in widget.selectedOrders) {
      if (order.hasCoordinates) {
        _markers.add(
          Marker(
            markerId: MarkerId(order.id),
            position: LatLng(order.latitude!, order.longitude!),
            infoWindow: InfoWindow(title: order.fullAddress),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      }
    }
  }

  Future<void> _getOptimizedRoute() async {
    if (widget.selectedOrders.isEmpty) return;

    final optimizedRoute = RoutingAlgorithms.nearestNeighborAlgorithm(
      widget.selectedOrders,
      widget.selectedOrders.first,
    );

    setState(() {
      _optimizedRoute = optimizedRoute;
      _createPolylines();
    });
  }

  void _createPolylines() {
    _polylines.clear();
    if (_optimizedRoute.length > 1) {
      for (int i = 0; i < _optimizedRoute.length - 1; i++) {
        final start = _optimizedRoute[i];
        final end = _optimizedRoute[i + 1];
        if (start.hasCoordinates && end.hasCoordinates) {
          _polylines.add(
            Polyline(
              polylineId: PolylineId('${start.id}-${end.id}'),
              color: Colors.blue,
              width: 5,
              points: [
                LatLng(start.latitude!, start.longitude!),
                LatLng(end.latitude!, end.longitude!),
              ],
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimized Route'),
        backgroundColor: const Color(0xFF0D2B0D),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              onMapCreated: (controller) => _mapController = controller,
              initialCameraPosition: CameraPosition(
                target: widget.selectedOrders.isNotEmpty && widget.selectedOrders.first.hasCoordinates
                    ? LatLng(widget.selectedOrders.first.latitude!, widget.selectedOrders.first.longitude!)
                    : const LatLng(0, 0), // Default to (0,0) if no orders or no coordinates
                zoom: 12,
              ),
              markers: _markers,
              polylines: _polylines,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _getOptimizedRoute,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D2B0D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Get Optimized Route'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
