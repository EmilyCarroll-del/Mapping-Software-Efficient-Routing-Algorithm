import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/route_optimization.dart';
import '../models/order.dart' as app_order;
import 'navigation_screen.dart';

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
    print('🗺️ Setting up map elements for Route Preview');

    final routePoints = widget.routeOptimization.routeGeometry
            ?.map((point) => LatLng(point[0], point[1]))
            .toList() ??
        [];

    if (routePoints.length >= 2) {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: routePoints,
          color: Colors.blue,
          width: 5,
        ),
      );
    }

    final majorStops = widget.routeOptimization.legs;

    if (majorStops.isNotEmpty) {
      for (int i = 0; i < majorStops.length; i++) {
        final step = majorStops[i];
        if (step.address.hasCoordinates) {
          _markers.add(
            Marker(
              markerId: MarkerId('stop_$i'),
              position: LatLng(step.address.latitude!, step.address.longitude!),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                i == 0 ? BitmapDescriptor.hueViolet : // Starting point
                i == 1 ? BitmapDescriptor.hueGreen  : // First stop (Pickup)
                BitmapDescriptor.hueRed,             // Subsequent stops (Dropoff)
              ),
              infoWindow: InfoWindow(
                title: step.address.fullAddress,
                snippet: i == 0 ? 'Start' : 'Stop $i',
              ),
            ),
          );
        }
      }
      print('✅ Added ${_markers.length} markers to the map.');
    }
  }


  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _fitMapToBounds();
  }

  void _fitMapToBounds() {
    if (_mapController == null) return;

    final route = widget.routeOptimization.legs;
    if (route.isEmpty) return;

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

  String _formatDistance(double km) {
    final miles = km * 0.621371;
    return '${miles.toStringAsFixed(1)} mi';
  }

  @override
  Widget build(BuildContext context) {
    final displaySteps = widget.routeOptimization.legs.length > 1
        ? widget.routeOptimization.legs.sublist(1)
        : <RouteStep>[];

    final pickup = displaySteps.isNotEmpty ? displaySteps.first.address : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Route Preview'),
        backgroundColor: const Color(0xFF0D2B0D),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: pickup != null && pickup.hasCoordinates
                    ? LatLng(pickup.latitude!, pickup.longitude!)
                    : const LatLng(40.7143, -73.5994), // Fallback
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
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: const Color(0xFF0D2B0D).withOpacity(0.1),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildSummaryItem(
                          Icons.route,
                          _formatDistance(widget.routeOptimization.totalDistance ?? 0),
                          'Distance',
                        ),
                        _buildSummaryItem(
                          Icons.access_time,
                          _formatDuration(widget.routeOptimization.estimatedTime),
                          'Duration',
                        ),
                        _buildSummaryItem(
                          Icons.location_on,
                          '${displaySteps.length}',
                          'Stops',
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: displaySteps.length,
                      itemBuilder: (context, index) {
                        final step = displaySteps[index];
                        final isPickup = index == 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPickup
                                  ? Colors.green
                                  : Colors.red,
                              child: Text(
                                '${index + 1}',
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
                            trailing: step.distanceFromPrevious != null &&
                                    step.distanceFromPrevious! > 0
                                ? Text(
                                    _formatDistance(step.distanceFromPrevious!),
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

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          routeOptimization: widget.routeOptimization,
          order: widget.order,
        ),
      ),
    );

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
