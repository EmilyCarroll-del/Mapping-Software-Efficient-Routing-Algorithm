import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:location/location.dart';

class LocationProvider extends ChangeNotifier {
  final Location _location = Location();
  LocationData? _currentLocation;
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isInitialized = false;

  LocationData? get currentLocation => _currentLocation;
  bool get isLocationAvailable => _currentLocation != null;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true; // Set early to prevent re-entry

    print('📍 [LocationProvider] Initializing...');

    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          print('❌ [LocationProvider] Location service not enabled.');
          return;
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          print('❌ [LocationProvider] Location permission not granted.');
          return;
        }
      }

      _currentLocation = await _location.getLocation();
      print('✅ [LocationProvider] Initial location: $_currentLocation');
      notifyListeners();

      _locationSubscription = _location.onLocationChanged.listen((LocationData newLocation) {
        _currentLocation = newLocation;
        notifyListeners();
      });

      print('✅ [LocationProvider] Initialized and listening for updates.');
    } catch (e) {
      print('❌ [LocationProvider] Initialization error: $e');
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }
}
