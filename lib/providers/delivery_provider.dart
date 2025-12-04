import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/delivery_address.dart';
import '../models/route_optimization.dart';
import '../services/firestore_service.dart';

class DeliveryProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  List<DeliveryAddress> _addresses = [];
  RouteOptimization? _route;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<List<DeliveryAddress>>? _addressSubscription;

  List<DeliveryAddress> get addresses => _addresses;
  RouteOptimization? get route => _route;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  DeliveryProvider(String userId) {
    if (userId.isNotEmpty) {
      fetchAddresses(userId);
    }
  }

  void fetchAddresses(String userId) {
    _addressSubscription?.cancel();
    // CORRECTED: Use 'getAddresses' instead of 'getAddressesStream'
    _addressSubscription = _firestoreService.getAddresses(userId).listen(
      (addresses) {
        _addresses = addresses;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = "Error fetching addresses: $error";
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> addAddress(DeliveryAddress address) async {
    try {
      _isLoading = true;
      notifyListeners();
      // CORRECTED: Use 'saveAddress' instead of 'addAddress'
      await _firestoreService.saveAddress(address);
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _errorMessage = "Failed to add address: $e";
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateAddress(DeliveryAddress address) async {
    try {
      // CORRECTED: Use 'saveAddress' instead of 'updateAddress'
      await _firestoreService.saveAddress(address);
      notifyListeners();
    } catch (e) {
      _errorMessage = "Failed to update address: $e";
      notifyListeners();
    }
  }

  Future<void> deleteAddress(String addressId) async {
    try {
      await _firestoreService.deleteAddress(addressId);
      notifyListeners();
    } catch (e) {
      _errorMessage = "Failed to delete address: $e";
      notifyListeners();
    }
  }

  Future<void> optimizeRoute(RouteAlgorithm algorithm) async {
    if (_addresses.length < 2) {
      _errorMessage = "At least 2 addresses are required to optimize a route.";
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      List<RouteStep> routeSteps = await _calculateOptimizedRoute(algorithm);
      final totalDistance = routeSteps.fold<double>(0, (sum, step) => sum + (step.distanceFromPrevious ?? 0));

      _route = RouteOptimization(
        name: '${algorithm.name.toUpperCase()} Optimized Route',
        addresses: _addresses, // You might need to reorder this list based on the route
        algorithm: algorithm,
        detailedSteps: routeSteps,
        legs: [], // Placeholder, as this algorithm doesn't define major legs
        totalDistance: totalDistance,
        estimatedTime: Duration(minutes: (totalDistance * 2).round()), // Rough estimate
        completedAt: DateTime.now(),
      );
    } catch (e) {
      _errorMessage = "Error optimizing route: $e";
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<RouteStep>> _calculateOptimizedRoute(RouteAlgorithm algorithm) async {
    // A simple placeholder for route calculation logic
    await Future.delayed(const Duration(seconds: 1)); 

    List<DeliveryAddress> unvisited = List.from(_addresses);
    List<RouteStep> routeSteps = [];
    DeliveryAddress currentAddress = unvisited.removeAt(0);
    
    routeSteps.add(RouteStep(sequenceNumber: 1, address: currentAddress, instructions: "Start"));

    int sequence = 2;
    while (unvisited.isNotEmpty) {
      DeliveryAddress nearest = _findNearest(currentAddress, unvisited);
      unvisited.remove(nearest);

      final distance = _calculateDistance(currentAddress, nearest);

      routeSteps.add(RouteStep(
        sequenceNumber: sequence++,
        address: nearest,
        instructions: "Proceed to next location",
        distanceFromPrevious: distance,
      ));
      currentAddress = nearest;
    }
    return routeSteps;
  }

  DeliveryAddress _findNearest(DeliveryAddress current, List<DeliveryAddress> others) {
    double minDistance = double.infinity;
    DeliveryAddress nearest = others.first;

    for (var other in others) {
      double distance = _calculateDistance(current, other);
      if (distance < minDistance) {
        minDistance = distance;
        nearest = other;
      }
    }
    return nearest;
  }

  double _calculateDistance(DeliveryAddress a, DeliveryAddress b) {
    if (a.latitude == null || a.longitude == null || b.latitude == null || b.longitude == null) {
      return 0;
    }
    var p = 0.017453292519943295; // Math.PI / 180
    var c = cos;
    var a1 = 0.5 - c((b.latitude! - a.latitude!) * p) / 2 +
        c(a.latitude! * p) * c(b.latitude! * p) *
        (1 - c((b.longitude! - a.longitude!) * p)) / 2;
    return 12742 * asin(sqrt(a1)); // 2 * R; R = 6371 km
  }

  String getAlgorithmDescription(RouteAlgorithm algorithm) {
    switch (algorithm) {
      case RouteAlgorithm.dijkstra:
        return "Dijkstra's: Finds the shortest path between nodes in a graph.";
      case RouteAlgorithm.prim:
        return "Prim's: Finds the minimum spanning tree for a weighted undirected graph.";
      case RouteAlgorithm.kruskal:
        return "Kruskal's: Finds a minimum spanning tree for a weighted undirected graph.";
      case RouteAlgorithm.fordBellman:
        return "Bellman-Ford: Finds shortest paths from a single source vertex to all other vertices.";
      case RouteAlgorithm.nearestNeighbor:
        return "Nearest Neighbor: A heuristic for solving the Traveling Salesperson Problem.";
      case RouteAlgorithm.aws:
        return "AWS Location: Uses Amazon's advanced routing and traffic data for optimization.";
    }
  }

  @override
  void dispose() {
    _addressSubscription?.cancel();
    super.dispose();
  }
}
