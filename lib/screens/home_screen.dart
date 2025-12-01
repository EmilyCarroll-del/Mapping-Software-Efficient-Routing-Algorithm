import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import '../providers/delivery_provider.dart';
import '../services/firestore_service.dart';
import '../utils/migrate_deliveries.dart';
import '../widgets/bottom_navigation_bar.dart';
import '../colors.dart';
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final Location _location = Location();
  LocationData? _currentLocation;
  bool _isLocationLoading = true;
  bool _locationPermissionGranted = false;

  // Hofstra University, Hempstead, NY
  static const LatLng _defaultLocation = LatLng(40.7143, -73.5994);

  Set<Marker> _markers = {};
  Set<Circle> _circles = {}; // For the pulsing effect
  
  // Animation for pulse
  late AnimationController _pulseController;
  
  bool _hasCenteredOnce = false;
  bool _followMe = true;

  // If true, keep the map centered on Hofstra University (fixed demo location)
  bool _useFixedHofstra = true;

  BitmapDescriptor? _customMarkerIcon;

  // Real order statistics
  final FirestoreService _firestoreService = FirestoreService();
  int _totalOrders = 0;
  int _completedOrders = 0;
  int _inProgressOrders = 0;

  // Bottom navigation
  int _currentIndex = 0;

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0:
      // Already on home
        break;
      case 1:
        context.go('/inbox');
        break;
      case 2:
        context.go('/profile');
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Initialize pulse animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // Slower duration for double wave
    )..repeat();
    
    // Listen to animation to update the circle
    _pulseController.addListener(() {
      if (_currentLocation != null) {
        _updatePulseCircle(_currentLocation!);
      }
    });

    _setup(); // Ensure marker icon loads before location-based markers
    _loadOrderStatistics();

    // Listen to authentication state changes
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {});
        if (user != null) {
          _loadOrderStatistics();
        }
      }
    });
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _updatePulseCircle(LocationData locationData) {
    if (locationData.latitude == null || locationData.longitude == null) return;
    
    // DOUBLE RIPPLE EFFECT
    // We generate two waves offset by 0.5 phase
    final double baseRadius = 20.0;
    final double maxRadius = 150.0; // even larger max radius

    // Wave 1
    final double progress1 = _pulseController.value;
    final double radius1 = baseRadius + (maxRadius - baseRadius) * progress1;
    final double opacity1 = (1.0 - progress1) * 0.6;

    // Wave 2 (Offset by 50%)
    final double progress2 = (_pulseController.value + 0.5) % 1.0;
    final double radius2 = baseRadius + (maxRadius - baseRadius) * progress2;
    final double opacity2 = (1.0 - progress2) * 0.6;
    
    final circle1 = Circle(
      circleId: const CircleId('pulse_circle_1'),
      center: LatLng(locationData.latitude!, locationData.longitude!),
      radius: radius1,
      fillColor: Colors.greenAccent.withOpacity(opacity1),
      strokeColor: Colors.greenAccent.withOpacity(opacity1 * 0.5),
      strokeWidth: 1,
    );

    final circle2 = Circle(
      circleId: const CircleId('pulse_circle_2'),
      center: LatLng(locationData.latitude!, locationData.longitude!),
      radius: radius2,
      fillColor: Colors.greenAccent.withOpacity(opacity2),
      strokeColor: Colors.greenAccent.withOpacity(opacity2 * 0.5),
      strokeWidth: 1,
    );
    
    // Solid Core Glow (Behind the triangle)
    final coreCircle = Circle(
      circleId: const CircleId('core_circle'),
      center: LatLng(locationData.latitude!, locationData.longitude!),
      radius: 30.0, // Larger core
      fillColor: Colors.green.withOpacity(0.5), // More visible core
      strokeColor: Colors.white.withOpacity(0.8), // Defined rim
      strokeWidth: 2,
    );

    setState(() {
      _circles = {circle1, circle2, coreCircle};
    });
  }

  /// Ensures we load the custom marker before we start placing markers on the map.
  Future<void> _setup() async {
    await _loadCustomMarker();
    await _initializeLocation();
  }

  // Load custom marker (simplified, no baked-in glow needed since we use Circle now)
  Future<void> _loadCustomMarker() async {
    try {
      // Standard size icon, the glow is handled by the map Circles
      final icon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(40, 40)),
        'assets/icons/tringle-icon.png',
      );
      
      if (!mounted) return;
      setState(() {
        _customMarkerIcon = icon;
      });

      // If we already know the location (e.g., in fixed Hofstra mode),
      // update the marker to use the loaded icon.
      if (_currentLocation != null) {
        await _updateDriverMarker(_currentLocation!);
      }
    } catch (e) {
      print('Error loading custom marker icon: $e');
      if (!mounted) return;
      setState(() {
        _customMarkerIcon =
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);
      });
    }
  }

  void _loadOrderStatistics() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen to total orders
    _firestoreService.getDriverAddressCount(user.uid).listen((count) {
      if (mounted) {
        setState(() {
          _totalOrders = count;
        });
      }
    });

    // Listen to completed orders
    _firestoreService.getDriverCompletedCount(user.uid).listen((count) {
      if (mounted) {
        setState(() {
          _completedOrders = count;
        });
      }
    });

    // Listen to in-progress orders
    _firestoreService.getDriverInProgressCount(user.uid).listen((count) {
      if (mounted) {
        setState(() {
          _inProgressOrders = count;
        });
      }
    });
  }

  Future<void> _updateDriverMarker(LocationData locationData) async {
    if (locationData.latitude == null || locationData.longitude == null) return;
    
    // Update the pulse circle position immediately
    _updatePulseCircle(locationData);

    // Use custom icon if loaded, otherwise fallback to default.
    final icon =
        _customMarkerIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue);

    final newMarker = Marker(
      markerId: const MarkerId('driver_location'),
      position: LatLng(locationData.latitude!, locationData.longitude!),
      icon: icon,
      rotation: locationData.heading ?? 0.0,
      flat: true, // Makes the marker rotate with the map
      anchor: const Offset(0.5, 0.5), // Center the icon
      infoWindow: const InfoWindow(title: 'You are here'),
    );

    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId.value == 'driver_location');
        _markers.add(newMarker);
      });
    }
  }

  Future<void> _initializeLocation() async {
    try {
      print('🗺️ Initializing location...');

      // Fixed Hofstra demo/location mode
      if (_useFixedHofstra) {
        _currentLocation = LocationData.fromMap({
          'latitude': _defaultLocation.latitude,
          'longitude': _defaultLocation.longitude,
          'accuracy': 100.0,
          'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
        });

        // Add initial marker
        await _updateDriverMarker(_currentLocation!);

        setState(() {
          _isLocationLoading = false;
          _locationPermissionGranted = false;
          _hasCenteredOnce = true;
          _followMe = false;
        });
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_defaultLocation),
          );
        }
        // Skip live location setup entirely
        return;
      }

      // Ensure location service is enabled
      bool serviceEnabled = await _location.serviceEnabled();
      print('📍 Location service enabled: $serviceEnabled');

      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        print('📍 Location service requested: $serviceEnabled');
      }

      // Request permission
      PermissionStatus permissionGranted = await _location.hasPermission();
      print('🔐 Location permission status: $permissionGranted');

      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        print('🔐 Location permission requested: $permissionGranted');
      }

      final granted = permissionGranted == PermissionStatus.granted ||
          permissionGranted == PermissionStatus.grantedLimited;

      if (!serviceEnabled || !granted) {
        setState(() {
          _isLocationLoading = false;
          _locationPermissionGranted = false;
        });
        return;
      }

      // Improve update quality
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 1000, // 1s updates
        distanceFilter: 1, // 1 meter
      );

      // Get current location once
      final current = await _location.getLocation();
      _currentLocation = current;

      await _updateDriverMarker(current);

      setState(() {
        _isLocationLoading = false;
        _locationPermissionGranted = true;
      });

      // Center camera once to current position
      if (_mapController != null &&
          current.latitude != null &&
          current.longitude != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(current.latitude!, current.longitude!),
          ),
        );
        _hasCenteredOnce = true;
      }

      // Listen to location changes
      _location.onLocationChanged.listen((LocationData locationData) {
        if (mounted) {
          print(
              '🔄 Location updated: ${locationData.latitude}, ${locationData.longitude}');
          _currentLocation = locationData;

          // Update marker position
          _updateDriverMarker(locationData);

          if (_mapController != null) {
            if (!_hasCenteredOnce || _followMe) {
              _mapController!.animateCamera(
                CameraUpdate.newLatLng(
                  LatLng(
                    locationData.latitude ?? _defaultLocation.latitude,
                    locationData.longitude ?? _defaultLocation.longitude,
                  ),
                ),
              );
              _hasCenteredOnce = true;
            }
          }
        }
      });
    } catch (e) {
      print('❌ Error getting location: $e');
      print(
          '📍 Using default location: ${_defaultLocation.latitude}, ${_defaultLocation.longitude}');

      // Fallback to Hofstra location
      _currentLocation = LocationData.fromMap({
        'latitude': _defaultLocation.latitude,
        'longitude': _defaultLocation.longitude,
        'accuracy': 100.0,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });

      await _updateDriverMarker(_currentLocation!);

      setState(() {
        _isLocationLoading = false;
        _locationPermissionGranted = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      print('📍 Manual location request...');
      final loc = await _location.getLocation();
      _currentLocation = loc;
      if (_mapController != null &&
          loc.latitude != null &&
          loc.longitude != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(
            LatLng(loc.latitude!, loc.longitude!),
          ),
        );
      }
      // Update marker
      await _updateDriverMarker(loc);

      setState(() {
        _hasCenteredOnce = true;
      });
    } catch (e) {
      print('❌ Error getting current location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen Google Maps
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              // Move to current location if available
              if (_currentLocation != null &&
                  _currentLocation!.latitude != null &&
                  _currentLocation!.longitude != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(
                      _currentLocation!.latitude!,
                      _currentLocation!.longitude!,
                    ),
                  ),
                );
              }
            },
            initialCameraPosition: CameraPosition(
              target: _currentLocation != null &&
                  _currentLocation!.latitude != null &&
                  _currentLocation!.longitude != null
                  ? LatLng(
                _currentLocation!.latitude!,
                _currentLocation!.longitude!,
              )
                  : _defaultLocation,
              zoom: 15,
            ),
            markers: _markers,
            circles: _circles, // Add our pulsing circles here
            mapType: MapType.normal,
            // We are using our own marker, so disable default myLocation blue dot
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            compassEnabled: true,
            mapToolbarEnabled: false,
            buildingsEnabled: true,
            trafficEnabled: false,
            indoorViewEnabled: true,
            tiltGesturesEnabled: true,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            zoomGesturesEnabled: true,
          ),

          // Top App Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.3),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // App Title
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GraphGo',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              'Route Optimization',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // User Actions
                      if (isLoggedIn) ...[
                        // Location Status
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _locationPermissionGranted
                                ? Colors.green.withOpacity(0.8)
                                : Colors.orange.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _locationPermissionGranted
                                    ? Icons.location_on
                                    : Icons.location_off,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _locationPermissionGranted
                                    ? 'Live'
                                    : 'Offline',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Notifications Button
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: kPrimaryColor,
                          child: IconButton(
                            icon: const Icon(Icons.notifications,
                                color: Colors.white, size: 20),
                            onPressed: () => context.go('/notifications'),
                            tooltip: 'Notifications',
                          ),
                        ),
                      ] else
                      // Login Button
                        ElevatedButton.icon(
                          onPressed: () => context.go('/login'),
                          icon: const Icon(Icons.login, size: 18),
                          label: const Text('Login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom Control Panel (only for logged-in users)
          if (isLoggedIn)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.black.withOpacity(0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Consumer<DeliveryProvider>(
                    builder: (context, deliveryProvider, child) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Quick Stats
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildQuickStat(
                                    'Total Orders',
                                    '$_totalOrders',
                                    Icons.assignment,
                                    kPrimaryColor,
                                  ),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: Colors.grey.withOpacity(0.3),
                                  ),
                                  _buildQuickStat(
                                    'In Progress',
                                    '$_inProgressOrders',
                                    Icons.hourglass_empty,
                                    Colors.orange,
                                  ),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: Colors.grey.withOpacity(0.3),
                                  ),
                                  _buildQuickStat(
                                    'Completed',
                                    '$_completedOrders',
                                    Icons.check_circle,
                                    Colors.green,
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            context.go('/assigned-orders'),
                                        icon: const Icon(Icons.assignment),
                                        label:
                                        const Text('Assigned Orders'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: kPrimaryColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                      // Notification badge for ongoing orders
                                      if (_inProgressOrders > 0)
                                        Positioned(
                                          right: 8,
                                          top: 8,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius:
                                              BorderRadius.circular(10),
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 20,
                                              minHeight: 20,
                                            ),
                                            child: Text(
                                              '$_inProgressOrders',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _totalOrders >= 2
                                        ? () => context.go('/optimize')
                                        : null,
                                    icon: const Icon(Icons.route),
                                    label: const Text('Optimize'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kAccentColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                        BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Temporary migration button - remove after migration is complete
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  await DeliveryMigration
                                      .migrateAcceptedAddressesToDeliveries();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            '✅ Migration completed! Check console for details.'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '❌ Migration failed: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.sync),
                              label: const Text('Migrate to Deliveries'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding:
                                const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),

          // Current Location Button (hidden in fixed Hofstra mode)
          if (!_useFixedHofstra)
            Positioned(
              bottom: isLoggedIn ? 200 : 100,
              right: 16,
              child: FloatingActionButton(
                onPressed: _getCurrentLocation,
                backgroundColor: Colors.white,
                foregroundColor: kPrimaryColor,
                child: const Icon(Icons.my_location),
                tooltip: 'Current Location',
              ),
            ),

          // Follow Me toggle (hidden in fixed Hofstra mode)
          if (!_useFixedHofstra)
            Positioned(
              bottom: isLoggedIn ? 140 : 60,
              right: 16,
              child: FloatingActionButton.small(
                onPressed: () {
                  setState(() {
                    _followMe = !_followMe;
                  });
                },
                backgroundColor:
                _followMe ? kPrimaryColor : Colors.white,
                foregroundColor:
                _followMe ? Colors.white : kPrimaryColor,
                tooltip: _followMe ? 'Following you' : 'Tap to follow',
                child: Icon(_followMe ? Icons.play_arrow : Icons.pause),
              ),
            ),

          // Loading Overlay
          if (_isLocationLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor:
                      AlwaysStoppedAnimation<Color>(kPrimaryColor),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Getting your location...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }

  Widget _buildQuickStat(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
