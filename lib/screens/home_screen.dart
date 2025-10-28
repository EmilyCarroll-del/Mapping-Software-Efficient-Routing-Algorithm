import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:location/location.dart';
import '../providers/delivery_provider.dart';
import '../services/firestore_service.dart';
import '../colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _mapController;
  final Location _location = Location();
  LocationData? _currentLocation;
  bool _isLocationLoading = true;
  bool _locationPermissionGranted = false;
  static const LatLng _defaultLocation = LatLng(40.7143, -73.5994); // Hofstra University, Hempstead, NY
  final Set<Marker> _markers = {};
  
  // Real order statistics
  final FirestoreService _firestoreService = FirestoreService();
  int _totalOrders = 0;
  int _completedOrders = 0;
  int _inProgressOrders = 0;
  int _activeOrders = 0;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
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

    _firestoreService.getDriverActiveCount(user.uid).listen((count) {
      if (mounted) {
        setState(() {
          _activeOrders = count;
        });
      }
    });
  }

  Future<void> _initializeLocation() async {
    try {
      print('🗺️ Initializing location...');
      
      // For now, let's force use Hofstra University location
      // This ensures the app always shows the correct location
      print('📍 Using Hofstra University as default location');
      _currentLocation = LocationData.fromMap({
        'latitude': _defaultLocation.latitude,
        'longitude': _defaultLocation.longitude,
        'accuracy': 100.0,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });
      
      print('✅ Location set to Hofstra: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      setState(() {
        _isLocationLoading = false;
        _locationPermissionGranted = true;
      });
      
      // Move camera to Hofstra location
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(_defaultLocation),
        );
      }

      // Check if location service is enabled for future updates
      bool serviceEnabled = await _location.serviceEnabled();
      print('📍 Location service enabled: $serviceEnabled');
      
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        print('📍 Location service requested: $serviceEnabled');
      }

      // Check location permission for future updates
      PermissionStatus permissionGranted = await _location.hasPermission();
      print('🔐 Location permission status: $permissionGranted');
      
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        print('🔐 Location permission requested: $permissionGranted');
      }

      // Listen to location changes (but keep Hofstra as fallback)
      _location.onLocationChanged.listen((LocationData locationData) {
        if (mounted) {
          print('🔄 Location updated: ${locationData.latitude}, ${locationData.longitude}');
          
          // Only update if we get a reasonable location (not Google HQ)
          // Check if the location is within reasonable bounds for Hofstra area
          if (locationData.latitude! > 40.0 && locationData.latitude! < 41.0 && 
              locationData.longitude! > -74.0 && locationData.longitude! < -73.0) {
            setState(() {
              _currentLocation = locationData;
            });
            
            // Update camera position
            if (_mapController != null) {
              _mapController!.animateCamera(
                CameraUpdate.newLatLng(
                  LatLng(locationData.latitude!, locationData.longitude!),
                ),
              );
            }
          } else {
            print('📍 Ignoring location update (outside Hofstra area)');
          }
        }
      });
    } catch (e) {
      print('❌ Error getting location: $e');
      print('📍 Using default location: ${_defaultLocation.latitude}, ${_defaultLocation.longitude}');
      
      // Fallback to Hofstra location
      _currentLocation = LocationData.fromMap({
        'latitude': _defaultLocation.latitude,
        'longitude': _defaultLocation.longitude,
        'accuracy': 100.0,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });
      
      setState(() {
        _isLocationLoading = false;
        _locationPermissionGranted = true;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      print('📍 Manual location request...');
      
      // Force use Hofstra University location
      _currentLocation = LocationData.fromMap({
        'latitude': _defaultLocation.latitude,
        'longitude': _defaultLocation.longitude,
        'accuracy': 100.0,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      });
      
      print('✅ Manual location set to Hofstra: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      
      if (_mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(_defaultLocation),
        );
      }
      setState(() {}); // Refresh UI
    } catch (e) {
      print('❌ Error setting location to Hofstra: $e');
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
              if (_currentLocation != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!),
                  ),
                );
              }
            },
            initialCameraPosition: CameraPosition(
              target: _currentLocation != null 
                  ? LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!)
                  : _defaultLocation,
              zoom: 15,
            ),
            markers: _markers,
            mapType: MapType.normal,
            myLocationEnabled: _locationPermissionGranted,
            myLocationButtonEnabled: false, // We'll add our own button
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                                _locationPermissionGranted ? Icons.location_on : Icons.location_off,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _locationPermissionGranted ? 'Live' : 'Offline',
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
                        // Profile Button
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: kPrimaryColor,
                          child: IconButton(
                            icon: const Icon(Icons.person, color: Colors.white, size: 20),
                            onPressed: () => context.go('/profile'),
                            tooltip: 'Profile',
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
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      ElevatedButton.icon(
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
                                      // Notification badge for ongoing orders
                                      if (_inProgressOrders > 0)
                                        Positioned(
                                          right: 8,
                                          top: 8,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: Colors.red,
                                              borderRadius: BorderRadius.circular(10),
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
                                    onPressed: _activeOrders > 0
                                        ? () async {
                                            if (user != null) {
                                              final activeOrders = await _firestoreService.getDriverActiveOrders(user.uid);
                                              context.go('/optimized-route-map', extra: activeOrders);
                                            }
                                          }
                                        : null,
                                    icon: const Icon(Icons.route),
                                    label: const Text('Optimize'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kAccentColor,
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
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          
          // Current Location Button
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
          
          // Loading Overlay
          if (_isLocationLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
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
    );
  }

  Widget _buildQuickStat(String label, String value, IconData icon, Color color) {
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
