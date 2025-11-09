import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/route_optimization.dart';
import '../models/order.dart' as app_order;
import 'navigation_screen.dart';

/// Route Preview Screen
/// 
/// Shows the calculated route on an embedded Google Maps with:
/// - Route polyline
/// - Pickup and dropoff markers
/// - Route summary (distance, time)
/// - List of directions
/// - "Start Navigation" button (like Uber/Lyft)
class RoutePreviewScreen extends StatefulWidget {
  final RouteOptimization routeOptimization;
  final app_order.Order order;

  const RoutePreviewScreen({
    super.key,
    required this.routeOptimization,
    required this.order,
  });

  @override
  State<RoutePreviewScreen> createState() => _RoutePreviewScreenState();
}

class _RoutePreviewScreenState extends State<RoutePreviewScreen> {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _setupMapElements();
  }

  void _setupMapElements() {
    print('🗺️ Setting up map elements');
    
    // Build polyline from route geometry
    List<LatLng> routePoints = [];
    
    if (widget.routeOptimization.routeGeometry != null &&
        widget.routeOptimization.routeGeometry!.isNotEmpty) {
      // Use AWS-provided geometry
      routePoints = widget.routeOptimization.routeGeometry!
          .map((point) => LatLng(point[0], point[1]))
          .toList();
      print('✅ Using ${routePoints.length} points from AWS geometry');
    } else {
      // Fallback: Create straight line from stops
      print('⚠️ No route geometry from AWS, creating fallback straight line');
      final route = widget.routeOptimization.optimizedRoute;
      if (route != null && route.isNotEmpty) {
        for (final step in route) {
          if (step.address.hasCoordinates) {
            routePoints.add(LatLng(step.address.latitude!, step.address.longitude!));
          }
        }
        print('✅ Created ${routePoints.length} points from stops');
      }
    }

    // Add polyline if we have points
    if (routePoints.length >= 2) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: Colors.blue,
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
      print('✅ Added polyline with ${routePoints.length} points to map');
    } else {
      print('⚠️ Not enough points for polyline');
    }

    // Add markers for stops
    final route = widget.routeOptimization.optimizedRoute;
    if (route != null && route.isNotEmpty) {
      // Pickup marker (first stop)
      final pickup = route.first.address;
      if (pickup.hasCoordinates) {
        _markers.add(
          Marker(
            markerId: const MarkerId('pickup'),
            position: LatLng(pickup.latitude!, pickup.longitude!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
            infoWindow: InfoWindow(
              title: 'Pickup',
              snippet: pickup.fullAddress,
            ),
          ),
        );
      }

      // Dropoff marker (last stop)
      final dropoff = route.last.address;
      if (dropoff.hasCoordinates) {
        _markers.add(
          Marker(
            markerId: const MarkerId('dropoff'),
            position: LatLng(dropoff.latitude!, dropoff.longitude!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: InfoWindow(
              title: 'Dropoff',
              snippet: dropoff.fullAddress,
            ),
          ),
        );
      }

      // Add intermediate waypoint markers
      for (int i = 1; i < route.length - 1; i++) {
        final waypoint = route[i].address;
        if (waypoint.hasCoordinates) {
          _markers.add(
            Marker(
              markerId: MarkerId('waypoint_$i'),
              position: LatLng(waypoint.latitude!, waypoint.longitude!),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
              infoWindow: InfoWindow(
                title: 'Stop ${i + 1}',
                snippet: waypoint.fullAddress,
              ),
            ),
          );
        }
      }

      print('✅ Added ${_markers.length} markers');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitMapToBounds();
  }

  void _fitMapToBounds() {
    if (_mapController == null) return;

    final route = widget.routeOptimization.optimizedRoute;
    if (route == null || route.isEmpty) return;

    // Calculate bounds from all addresses
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final step in route) {
      if (step.address.hasCoordinates) {
        final lat = step.address.latitude!;
        final lng = step.address.longitude!;
        if (lat < minLat) minLat = lat;
        if (lat > maxLat) maxLat = lat;
        if (lng < minLng) minLng = lng;
        if (lng > maxLng) maxLng = lng;
      }
    }

    if (minLat != double.infinity) {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 50), // 50 padding
      );
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'N/A';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.routeOptimization.optimizedRoute ?? [];
    final pickup = route.isNotEmpty ? route.first.address : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Preview'),
        backgroundColor: const Color(0xFF0D2B0D),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Map showing route
          Expanded(
            flex: 3,
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: pickup != null && pickup.hasCoordinates
                    ? LatLng(pickup.latitude!, pickup.longitude!)
                    : const LatLng(37.7749, -122.4194), // Default SF
                zoom: 12,
              ),
              polylines: _polylines,
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              mapType: MapType.normal,
              zoomControlsEnabled: false,
            ),
          ),

          // Route summary and directions
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Route summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: const Color(0xFF0D2B0D).withOpacity(0.1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(
                          Icons.route,
                          '${(widget.routeOptimization.totalDistance ?? 0).toStringAsFixed(1)} km',
                          'Distance',
                        ),
                        _buildSummaryItem(
                          Icons.access_time,
                          _formatDuration(widget.routeOptimization.estimatedTime),
                          'Duration',
                        ),
                        _buildSummaryItem(
                          Icons.location_on,
                          '${route.length}',
                          'Stops',
                        ),
                      ],
                    ),
                  ),

                  // Directions list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: route.length,
                      itemBuilder: (context, index) {
                        final step = route[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: index == 0
                                  ? Colors.green
                                  : (index == route.length - 1
                                      ? Colors.red
                                      : Colors.blue),
                              child: Text(
                                '${step.sequenceNumber}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              step.address.fullAddress,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: step.instructions != null
                                ? Text(step.instructions!)
                                : null,
                            trailing: step.distanceFromPrevious != null &&
                                    step.distanceFromPrevious! > 0
                                ? Text(
                                    '${step.distanceFromPrevious!.toStringAsFixed(1)} km',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () => _startNavigation(),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D2B0D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.navigation, size: 24),
              SizedBox(width: 8),
              Text(
                'Start Navigation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF0D2B0D)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _startNavigation() async {
    print('🚀 Starting navigation');
    
    // Update order status to in_progress
    try {
      await FirebaseFirestore.instance
          .collection(widget.order.sourceCollection)
          .doc(widget.order.id)
          .update({
        'status': 'in_progress',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('✅ Order status updated to in_progress');
    } catch (e) {
      print('❌ Error updating order status: $e');
    }

    if (!mounted) return;

    // Navigate to full-screen navigation
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          routeOptimization: widget.routeOptimization,
          order: widget.order,
        ),
      ),
    );

    // After navigation completes, return to previous screen if delivery finished
    if (mounted && result == 'completed') {
      Navigator.pop(context, 'completed');
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

