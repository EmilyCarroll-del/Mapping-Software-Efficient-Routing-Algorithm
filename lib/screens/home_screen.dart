import 'dart:async';

import 'package:flutter/material.dart';
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
import '../widgets/driver_marker.dart';

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
  static const LatLng _defaultLocation = LatLng(40.7143, -73.5994);
  Set<Marker> _markers = {};
  Set<Circle> _circles = {}; // For the pulsing effect
  late AnimationController _pulseController;
  bool _hasCenteredOnce = false;
  bool _followMe = true;
  bool _useFixedHofstra = true;

  final FirestoreService _firestoreService = FirestoreService();
  int _totalOrders = 0;
  int _completedOrders = 0;
  int _inProgressOrders = 0;

  int _currentIndex = 0;

  late final StreamSubscription<User?> _authSub;

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0:
      // home
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _pulseController.addListener(() {
      if (_currentLocation != null) {
        _updateDriverMarker(_currentLocation!);
      }
    });
    _setup();
    _loadOrderStatistics();

    _authSub = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (!mounted) return;
      setState(() {}); // rebuild to reflect login/logout state
      if (user != null) {
        _loadOrderStatistics();
      }
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    await DriverMarker.loadCustomMarker();
    await _initializeLocation();
  }

  void _loadOrderStatistics() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _firestoreService.getDriverAddressCount(user.uid).listen((count) {
      if (mounted) {
        setState(() {
          _totalOrders = count;
        });
      }
    });

    _firestoreService.getDriverCompletedCount(user.uid).listen((count) {
      if (mounted) {
        setState(() {
          _completedOrders = count;
        });
      }
    });

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

    final newMarker = DriverMarker.getMarker(locationData);
    final newCircles = DriverMarker.getPulseCircles(_pulseController, locationData);

    if (mounted) {
      setState(() {
        _markers = {newMarker};
        _circles = newCircles;
      });
    }
  }

  Future<void> _initializeLocation() async {
    try {
      if (_useFixedHofstra) {
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
          _hasCenteredOnce = true;
          _followMe = false;
        });
        if (_mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(_defaultLocation),
          );
        }
        return;
      }

      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
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

      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 1000,
        distanceFilter: 1,
      );

      final current = await _location.getLocation();
      _currentLocation = current;
      await _updateDriverMarker(current);
      setState(() {
        _isLocationLoading = false;
        _locationPermissionGranted = true;
      });

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

      _location.onLocationChanged.listen((LocationData locationData) {
        if (mounted) {
          _currentLocation = locationData;
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
      await _updateDriverMarker(loc);
      setState(() {
        _hasCenteredOnce = true;
      });
    } catch (e) {
      // silently ignore for now
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              if (_currentLocation != null) {
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
              target: _currentLocation != null
                  ? LatLng(
                _currentLocation!.latitude!,
                _currentLocation!.longitude!,
              )
                  : _defaultLocation,
              zoom: 15,
            ),
            markers: _markers,
            circles: _circles,
            mapType: MapType.normal,
            myLocationEnabled: false,
            myLocationButtonEnabled:
            false,
          ),

          // TOP BAR
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(isLoggedIn),
          ),

          // BOTTOM PANEL
          if (isLoggedIn)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomPanel(context),
            ),

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
                      style: TextStyle(color: Colors.white, fontSize: 16),
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

  Widget _buildTopBar(bool isLoggedIn) {
    return Container(
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
              // App title
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
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Route Optimization',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Right-side actions
              if (isLoggedIn) ...[
                _buildLocationBadge(),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: kPrimaryColor,
                  child: IconButton(
                    icon: const Icon(
                      Icons.notifications,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () => context.go('/notifications'),
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () => context.go('/login'),
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _locationPermissionGranted
            ? Colors.green.withOpacity(0.8)
            : Colors.orange.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
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
            _locationPermissionGranted ? 'Live' : 'Offline',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context) {
    return Container(
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
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => context.go('/assigned-orders'),
                          icon: const Icon(Icons.assignment),
                          label: const Text('Assigned Orders'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
    );
  }

  Widget _buildQuickStat(
      String label,
      String value,
      IconData icon,
      Color color,
      ) {
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
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
