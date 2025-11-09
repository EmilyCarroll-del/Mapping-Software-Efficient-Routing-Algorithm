import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import '../models/route_optimization.dart';
import '../models/order.dart' as app_order;
import 'dart:math' as math;
import 'delivery_invoice_screen.dart';

/// Navigation Screen
///
/// Full-screen Google Maps with live navigation (like Uber/Lyft):
/// - Route polyline drawn on map
/// - Driver's current location tracked in real-time
/// - Map auto-centers on driver position
/// - Shows next turn/instruction
/// - "Complete Delivery" button
class NavigationScreen extends StatefulWidget {
  final RouteOptimization routeOptimization;
  final app_order.Order order;

  const NavigationScreen({
    super.key,
    required this.routeOptimization,
    required this.order,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  GoogleMapController? _mapController;
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  loc.Location location = loc.Location();
  StreamSubscription<loc.LocationData>? _locationSubscription;
  loc.LocationData? _currentLocation;
  loc.LocationData? _lastValidLocation;

  int _currentStopIndex = 0;
  bool _isNavigating = true;
  bool _isIgnoringGps = false;
  bool _hasShownGpsWarning = false;
  late final DateTime _navigationStartTime;
  static const double _gpsIgnoreThresholdKm = 5;

  @override
  void initState() {
    super.initState();
    _navigationStartTime = DateTime.now();
    _setupMap();
    _startLocationTracking();
  }

  void _setupMap() {
    print('🗺️ Setting up navigation map');

    // Build polyline from route geometry
    List<LatLng> routePoints = [];

    final geometry = widget.routeOptimization.routeGeometry;
    if (geometry != null && geometry.isNotEmpty) {
      routePoints =
          geometry.map((point) => LatLng(point[0], point[1])).toList();
      print('✅ Using ${routePoints.length} points from AWS geometry');
    }

    if (routePoints.length < 2) {
      // Fallback: Create straight line from stops
      print('⚠️ No route geometry, creating straight line from stops');
      final route = widget.routeOptimization.optimizedRoute;
      if (route != null && route.isNotEmpty) {
        for (final step in route) {
          if (step.address.hasCoordinates) {
            routePoints
                .add(LatLng(step.address.latitude!, step.address.longitude!));
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
          color: const Color(0xFF0D2B0D),
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
      print('✅ Added navigation polyline with ${routePoints.length} points');
    } else {
      print('⚠️ Not enough points for navigation polyline');
    }

    // Add markers
    final route = widget.routeOptimization.optimizedRoute;
    if (route != null && route.isNotEmpty) {
      for (int i = 0; i < route.length; i++) {
        final step = route[i];
        if (step.address.hasCoordinates) {
          BitmapDescriptor icon;
          String title;

          if (i == 0) {
            icon = BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen);
            title = 'Pickup';
          } else if (i == route.length - 1) {
            icon =
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
            title = 'Final Dropoff';
          } else {
            icon =
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
            title = 'Stop ${i + 1}';
          }

          _markers.add(
            Marker(
              markerId: MarkerId('stop_$i'),
              position: LatLng(step.address.latitude!, step.address.longitude!),
              icon: icon,
              infoWindow: InfoWindow(
                title: title,
                snippet: step.address.fullAddress,
              ),
            ),
          );
        }
      }
    }

    // Ensure route points include at least the stop anchors
    final stopAnchors = _routeStops();
    if (stopAnchors.isNotEmpty) {
      if (routePoints.isEmpty) {
        routePoints = stopAnchors;
      } else {
        // prepend/append anchors if missing
        final start = stopAnchors.first;
        final end = stopAnchors.last;
        if (routePoints.isEmpty ||
            _distanceBetweenLatLng(routePoints.first, start) > 0.05) {
          routePoints = [start, ...routePoints];
        } else {
          routePoints[0] = start;
        }
        if (_distanceBetweenLatLng(routePoints.last, end) > 0.05) {
          routePoints = [...routePoints, end];
        } else {
          routePoints[routePoints.length - 1] = end;
        }
      }
    }
  }

  List<LatLng> _routeStops() {
    final route = widget.routeOptimization.optimizedRoute;
    if (route == null) return [];
    return route
        .where((step) => step.address.hasCoordinates)
        .map((step) => LatLng(step.address.latitude!, step.address.longitude!))
        .toList();
  }

  double _distanceBetweenLatLng(LatLng a, LatLng b) =>
      _calculateDistance(a.latitude, a.longitude, b.latitude, b.longitude);

  bool _shouldIgnoreLocationUpdate(double latitude, double longitude) {
    final stops = _routeStops();
    if (stops.isEmpty) return false;

    final currentStop = stops[math.min(_currentStopIndex, stops.length - 1)];
    final distanceToCurrent = _calculateDistance(
        latitude, longitude, currentStop.latitude, currentStop.longitude);

    if (distanceToCurrent <= _gpsIgnoreThresholdKm) {
      return false;
    }

    for (final stop in stops) {
      final distance = _calculateDistance(
          latitude, longitude, stop.latitude, stop.longitude);
      if (distance <= _gpsIgnoreThresholdKm) {
        return false;
      }
    }

    return true;
  }

  void _focusOnCurrentStop() {
    final route = widget.routeOptimization.optimizedRoute;
    if (_mapController == null || route == null || route.isEmpty) return;
    final index = math.min(_currentStopIndex, route.length - 1);
    final currentStop = route[index];
    if (!currentStop.address.hasCoordinates) return;

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(
            currentStop.address.latitude!,
            currentStop.address.longitude!,
          ),
          zoom: 16,
          tilt: 45,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.routeOptimization.optimizedRoute;
    final currentStop = route != null && _currentStopIndex < route.length
        ? route[_currentStopIndex]
        : null;

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen Google Map
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _focusOnCurrentStop();
            },
            initialCameraPosition: CameraPosition(
              target: currentStop != null && currentStop.address.hasCoordinates
                  ? LatLng(currentStop.address.latitude!,
                      currentStop.address.longitude!)
                  : const LatLng(37.7749, -122.4194),
              zoom: 16,
              tilt: 45,
            ),
            polylines: _polylines,
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // We'll use custom button
            mapType: MapType.normal,
            zoomControlsEnabled: false,
            compassEnabled: true,
          ),

          if (_isIgnoringGps)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 140,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.orange[100],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GPS signal appears far from the route. Staying focused on stop locations.',
                          style: TextStyle(color: Colors.orange[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Top card showing next instruction
          if (currentStop != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: _currentStopIndex == 0
                                ? Colors.green
                                : (_currentStopIndex == route!.length - 1
                                    ? Colors.red
                                    : Colors.blue),
                            child: Text(
                              '${_currentStopIndex + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentStopIndex == 0 ? 'Pickup' : 'Dropoff',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  currentStop.address.fullAddress,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (currentStop.instructions != null) ...[
                        const Divider(height: 16),
                        Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                currentStop.instructions!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (currentStop.distanceFromPrevious != null &&
                          currentStop.distanceFromPrevious! > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${currentStop.distanceFromPrevious!.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

          // Bottom action buttons
          Positioned(
            bottom: 32,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Recenter button
                Align(
                  alignment: Alignment.centerRight,
                  child: FloatingActionButton(
                    heroTag: 'recenter',
                    onPressed: _recenterMap,
                    backgroundColor: Colors.white,
                    child:
                        const Icon(Icons.my_location, color: Color(0xFF0D2B0D)),
                  ),
                ),
                const SizedBox(height: 16),

                // Complete stop button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _completeCurrentStop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D2B0D),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle),
                        const SizedBox(width: 8),
                        Text(
                          _currentStopIndex ==
                                  (widget.routeOptimization.optimizedRoute
                                              ?.length ??
                                          1) -
                                      1
                              ? 'Complete Delivery'
                              : 'Complete Stop ${_currentStopIndex + 1}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.black),
                onPressed: () => _confirmExit(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startLocationTracking() async {
    print('📍 Starting real-time location tracking');

    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) return;
      }

      loc.PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == loc.PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != loc.PermissionStatus.granted) return;
      }

      // Configure location settings for navigation
      await location.changeSettings(
        accuracy: loc.LocationAccuracy.high,
        interval: 1000, // Update every second
        distanceFilter: 10, // Update if moved 10 meters
      );

      _locationSubscription = location.onLocationChanged.listen((locationData) {
        if (!mounted) return;

        if (locationData.latitude != null && locationData.longitude != null) {
          final shouldIgnore = _shouldIgnoreLocationUpdate(
            locationData.latitude!,
            locationData.longitude!,
          );

          if (shouldIgnore) {
            if (!_hasShownGpsWarning) {
              _hasShownGpsWarning = true;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'GPS location far from route. Ignoring emulator position.'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
            setState(() {
              _isIgnoringGps = true;
            });
            _focusOnCurrentStop();
            return;
          } else if (_isIgnoringGps) {
            setState(() {
              _isIgnoringGps = false;
            });
          }
        }

        setState(() {
          _currentLocation = locationData;
          _lastValidLocation = locationData;
        });

        if (!_isIgnoringGps &&
            _mapController != null &&
            locationData.latitude != null &&
            locationData.longitude != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(locationData.latitude!, locationData.longitude!),
                zoom: 17,
                tilt: 45,
                bearing: locationData.heading ?? 0,
              ),
            ),
          );
        }

        _checkStopProximity(locationData);
      });

      print('✅ Location tracking active');
    } catch (e) {
      print('❌ Error starting location tracking: $e');
    }
  }

  void _checkStopProximity(loc.LocationData locationData) {
    if (locationData.latitude == null || locationData.longitude == null) return;

    final route = widget.routeOptimization.optimizedRoute;
    if (route == null || _currentStopIndex >= route.length) return;

    final currentStop = route[_currentStopIndex].address;
    if (!currentStop.hasCoordinates) return;

    final distance = _calculateDistance(
      locationData.latitude!,
      locationData.longitude!,
      currentStop.latitude!,
      currentStop.longitude!,
    );

    // If within 50 meters, show arrival notification
    if (distance < 0.05) {
      // 0.05 km = 50 meters
      if (!_isNavigating) return; // Already notified

      setState(() {
        _isNavigating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Arrived at ${currentStop.fullAddress}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * (math.pi / 180);

  void _recenterMap() {
    final locationSource =
        !_isIgnoringGps ? (_lastValidLocation ?? _currentLocation) : null;
    if (locationSource != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(locationSource.latitude!, locationSource.longitude!),
            zoom: 17,
            tilt: 45,
            bearing: locationSource.heading ?? 0,
          ),
        ),
      );
    } else {
      _focusOnCurrentStop();
    }
  }

  void _completeCurrentStop() {
    final route = widget.routeOptimization.optimizedRoute;
    if (route == null) return;

    final isLastStop =
        _currentStopIndex >= (route.length - 1);

    if (isLastStop) {
      // All stops completed
      _completeDelivery();
    } else {
      setState(() {
        _currentStopIndex++;
        _isNavigating = true;
      });
      _focusOnCurrentStop();
      // Move to next stop
      final nextStop = route[_currentStopIndex];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Next: ${nextStop.address.fullAddress}'),
          duration: const Duration(seconds: 3),
        ),
      );

      // Pan map to next stop
      if (_mapController != null && nextStop.address.hasCoordinates) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(nextStop.address.latitude!, nextStop.address.longitude!),
            15,
          ),
        );
      }
    }
  }

  Future<void> _completeDelivery() async {
    print('🎉 Completing delivery');
    final endTime = DateTime.now();
    final actualDuration = endTime.difference(_navigationStartTime);

    final invoiceRoute = RouteOptimization(
      id: widget.routeOptimization.id,
      name: widget.routeOptimization.name,
      addresses: widget.routeOptimization.addresses,
      algorithm: widget.routeOptimization.algorithm,
      createdAt: widget.routeOptimization.createdAt,
      completedAt: endTime,
      optimizedRoute: widget.routeOptimization.optimizedRoute,
      totalDistance: widget.routeOptimization.totalDistance,
      estimatedTime: widget.routeOptimization.estimatedTime,
      routeGeometry: widget.routeOptimization.routeGeometry,
      encodedPolyline: widget.routeOptimization.encodedPolyline,
    );

    if (!mounted) return;

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => DeliveryInvoiceScreen(
          order: widget.order,
          routeOptimization: invoiceRoute,
          actualDuration: actualDuration,
          startTime: _navigationStartTime,
          endTime: endTime,
        ),
      ),
    );

    if (!mounted) return;

    if (result == 'completed') {
      Navigator.of(context).pop('completed');
    }
  }

  void _confirmExit() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Navigation?'),
        content: const Text(
            'Are you sure you want to exit navigation? The route will remain in progress.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Exit navigation
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }
}
