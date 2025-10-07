import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';
import '../models/route_optimization.dart';
import '../services/routing_algorithms.dart';
import '../services/geocoding_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

class DeliveryProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<DeliveryAddress> _addresses = [];
  List<RouteOptimization> _routeOptimizations = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<DeliveryAddress> get addresses => List.unmodifiable(_addresses);
  List<RouteOptimization> get routeOptimizations => List.unmodifiable(_routeOptimizations);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasAddresses => _addresses.isNotEmpty;
  int get addressCount => _addresses.length;
  bool get canAddMoreAddresses => _addresses.length < 100;

  // Initialize provider
  Future<void> initialize() async {
    await _loadAddresses();
    await _loadRouteOptimizations();
  }

  // Address Management
  // lib/providers/delivery_provider.dart

  Future<void> addAddress(DeliveryAddress address) async {
    if (!canAddMoreAddresses) {
      _error = 'Maximum of 100 addresses allowed';
      notifyListeners();
      return;
    }

    _setLoading(true);
    try {
      // ⬇️ NEW: if address already has coords, skip geocoding
      final DeliveryAddress ready = address.hasCoordinates
          ? address
          : await GeocodingService.geocodeAddress(address);

      // Add to local list
      _addresses.add(ready);

      // Save to Firestore
      await _saveAddressToFirestore(ready);

      _error = null;
    } catch (e) {
      _error = 'Failed to add address: ${e.toString()}';
      // If we added the raw address above, we *didn't* — so no need to remove.
    } finally {
      _setLoading(false);
    }
  }


  Future<void> updateAddress(DeliveryAddress address) async {
    _setLoading(true);
    try {
      // Geocode the updated address
      final geocodedAddress = await GeocodingService.geocodeAddress(address);

      // Update local list
      final index = _addresses.indexWhere((a) => a.id == address.id);
      if (index != -1) {
        _addresses[index] = geocodedAddress;
      }

      // Update in Firestore
      await _updateAddressInFirestore(geocodedAddress);

      _error = null;
    } catch (e) {
      _error = 'Failed to update address: ${e.toString()}';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> removeAddress(String addressId) async {
    _setLoading(true);
    try {
      // Remove from local list
      _addresses.removeWhere((a) => a.id == addressId);

      // Remove from Firestore
      await _removeAddressFromFirestore(addressId);

      _error = null;
    } catch (e) {
      _error = 'Failed to remove address: ${e.toString()}';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> geocodeAllAddresses() async {
    _setLoading(true);
    try {
      final addressesToGeocode = _addresses.where((a) => !a.hasCoordinates).toList();

      if (addressesToGeocode.isEmpty) {
        _setLoading(false);
        return;
      }

      final geocodedAddresses = await GeocodingService.geocodeAddresses(addressesToGeocode);

      // Update addresses with coordinates
      for (final geocodedAddress in geocodedAddresses) {
        final index = _addresses.indexWhere((a) => a.id == geocodedAddress.id);
        if (index != -1) {
          _addresses[index] = geocodedAddress;
        }
      }

      // Update in Firestore
      for (final address in geocodedAddresses) {
        await _updateAddressInFirestore(address);
      }

      _error = null;
    } catch (e) {
      _error = 'Failed to geocode addresses: ${e.toString()}';
    } finally {
      _setLoading(false);
    }
  }

  // Route Optimization
  Future<RouteOptimization> optimizeRoute({
    required String name,
    required RouteAlgorithm algorithm,
    DeliveryAddress? startAddress,
  }) async {
    if (_addresses.isEmpty) {
      throw Exception('No addresses available for route optimization');
    }

    _setLoading(true);
    try {
      final start = startAddress ?? _addresses.first;
      List<DeliveryAddress> optimizedRoute;

      switch (algorithm) {
        case RouteAlgorithm.dijkstra:
          optimizedRoute = RoutingAlgorithms.dijkstraAlgorithm(_addresses, start);
          break;
        case RouteAlgorithm.prim:
          optimizedRoute = RoutingAlgorithms.primAlgorithm(_addresses, start);
          break;
        case RouteAlgorithm.kruskal:
          optimizedRoute = RoutingAlgorithms.kruskalAlgorithm(_addresses, start);
          break;
        case RouteAlgorithm.fordBellman:
          optimizedRoute = RoutingAlgorithms.fordBellmanAlgorithm(_addresses, start);
          break;
        case RouteAlgorithm.nearestNeighbor:
          optimizedRoute = RoutingAlgorithms.nearestNeighborAlgorithm(_addresses, start);
          break;
      }

      // Calculate total distance and estimated time
      double totalDistance = 0;
      final routeSteps = <RouteStep>[];

      for (int i = 0; i < optimizedRoute.length; i++) {
        final currentAddress = optimizedRoute[i];
        double distanceFromPrevious = 0;

        if (i > 0) {
          final previousAddress = optimizedRoute[i - 1];
          if (currentAddress.hasCoordinates && previousAddress.hasCoordinates) {
            distanceFromPrevious = RoutingAlgorithms.calculateDistance(
              previousAddress.latitude!, previousAddress.longitude!,
              currentAddress.latitude!, currentAddress.longitude!,
            );
            totalDistance += distanceFromPrevious;
          }
        }

        routeSteps.add(RouteStep(
          sequenceNumber: i + 1,
          address: currentAddress,
          distanceFromPrevious: distanceFromPrevious,
          estimatedTravelTime: Duration(minutes: (distanceFromPrevious * 2).round()), // Assume 30 km/h average
          instructions: _generateInstructions(currentAddress, i),
        ));
      }

      final routeOptimization = RouteOptimization(
        name: name,
        addresses: optimizedRoute,
        algorithm: algorithm,
        optimizedRoute: routeSteps,
        totalDistance: totalDistance,
        estimatedTime: Duration(minutes: (totalDistance * 2).round()),
        completedAt: DateTime.now(),
      );

      // Add to local list
      _routeOptimizations.add(routeOptimization);

      // Save to Firestore
      await _saveRouteOptimizationToFirestore(routeOptimization);

      _error = null;
      return routeOptimization;
    } catch (e) {
      _error = 'Failed to optimize route: ${e.toString()}';
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> deleteRouteOptimization(String routeId) async {
    _setLoading(true);
    try {
      // Remove from local list
      _routeOptimizations.removeWhere((r) => r.id == routeId);

      // Remove from Firestore
      await _removeRouteOptimizationFromFirestore(routeId);

      _error = null;
    } catch (e) {
      _error = 'Failed to delete route: ${e.toString()}';
    } finally {
      _setLoading(false);
    }
  }

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  String _generateInstructions(DeliveryAddress address, int sequenceNumber) {
    if (sequenceNumber == 0) {
      return 'Start your route at ${address.fullAddress}';
    } else {
      return 'Deliver to ${address.fullAddress}';
    }
  }

  // Firestore operations
  Future<void> _loadAddresses() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('addresses')
          .orderBy('createdAt', descending: true)
          .get();

      _addresses = snapshot.docs
          .map((doc) => DeliveryAddress.fromJson(doc.data()))
          .toList();

      notifyListeners();
    } catch (e) {
      _error = 'Failed to load addresses: ${e.toString()}';
    }
  }

  Future<void> _loadRouteOptimizations() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('routeOptimizations')
          .orderBy('createdAt', descending: true)
          .get();

      _routeOptimizations = snapshot.docs
          .map((doc) => RouteOptimization.fromJson(doc.data()))
          .toList();

      notifyListeners();
    } catch (e) {
      _error = 'Failed to load route optimizations: ${e.toString()}';
    }
  }

  Future<void> _saveAddressToFirestore(DeliveryAddress address) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('addresses')
        .doc(address.id)
        .set(address.toJson());
  }

  Future<void> _updateAddressInFirestore(DeliveryAddress address) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('addresses')
        .doc(address.id)
        .update(address.toJson());
  }

  Future<void> _removeAddressFromFirestore(String addressId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('addresses')
        .doc(addressId)
        .delete();
  }

  Future<void> _saveRouteOptimizationToFirestore(RouteOptimization route) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('routeOptimizations')
        .doc(route.id)
        .set(route.toJson());
  }

  Future<void> _removeRouteOptimizationFromFirestore(String routeId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('routeOptimizations')
        .doc(routeId)
        .delete();
  }
}



// ===== T9 ADAPTER: expose start and stops as LatLngs for the router =====
extension T9DeliveryAdapter on DeliveryProvider {
  /// Start location for routing. Using the first geocoded address as the start.
  gmap.LatLng? get startLocation {
    if (_addresses.isEmpty) return null;

    // Prefer the first address that already has coordinates; otherwise null.
    final firstWithCoords = _addresses.firstWhere(
          (a) => a.hasCoordinates,
      orElse: () => _addresses.first,
    );
    if (firstWithCoords.hasCoordinates) {
      return gmap.LatLng(firstWithCoords.latitude!, firstWithCoords.longitude!);
    }
    return null;
  }

  /// Unordered stops (skips the first entry if you treat it as the start).
  List<gmap.LatLng> get stops {
    if (_addresses.length <= 1) return const [];
    final list = _addresses
        .skip(1)
        .where((a) => a.hasCoordinates)
        .map((a) => gmap.LatLng(a.latitude!, a.longitude!));
    return List<gmap.LatLng>.from(list);
  }
}

