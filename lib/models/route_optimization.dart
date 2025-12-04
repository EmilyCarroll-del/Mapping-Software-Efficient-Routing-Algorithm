import 'package:uuid/uuid.dart';
import 'delivery_address.dart';

enum RouteAlgorithm {
  dijkstra,
  prim,
  kruskal,
  fordBellman,
  nearestNeighbor,
  aws,
}

class RouteOptimization {
  final String id;
  final String name;
  final List<DeliveryAddress> addresses;
  final RouteAlgorithm algorithm;
  final DateTime createdAt;
  final DateTime? completedAt;

  // --- FIX: Renamed for clarity and added a new list for major stops ---
  final List<RouteStep> detailedSteps; // All turn-by-turn steps
  final List<RouteStep> legs; // Just the major start/pickup/dropoff stops

  final double? totalDistance;
  final Duration? estimatedTime;
  final List<List<double>>? routeGeometry; // [[lat, lng], [lat, lng], ...] for map polyline
  final String? encodedPolyline; // Optional: encoded polyline

  RouteOptimization({
    String? id,
    required this.name,
    required this.addresses,
    required this.algorithm,
    required this.detailedSteps,
    required this.legs,
    DateTime? createdAt,
    this.completedAt,
    this.totalDistance,
    this.estimatedTime,
    this.routeGeometry,
    this.encodedPolyline,
  }) : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  // Helper to maintain compatibility with older code if needed
  List<RouteStep> get optimizedRoute => detailedSteps;

  bool get isCompleted => completedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'addresses': addresses.map((a) => a.toJson()).toList(),
    'algorithm': algorithm.name,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'detailedSteps': detailedSteps.map((s) => s.toJson()).toList(),
    'legs': legs.map((s) => s.toJson()).toList(),
    'totalDistance': totalDistance,
    'estimatedTime': estimatedTime?.inMinutes,
    'routeGeometry': routeGeometry,
    'encodedPolyline': encodedPolyline,
  };

  factory RouteOptimization.fromJson(Map<String, dynamic> json) => RouteOptimization(
    id: json['id'],
    name: json['name'],
    addresses: (json['addresses'] as List)
        .map((a) => DeliveryAddress.fromJson(a))
        .toList(),
    algorithm: RouteAlgorithm.values.firstWhere(
          (e) => e.name == json['algorithm'],
    ),
    createdAt: DateTime.parse(json['createdAt']),
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'])
        : null,
    detailedSteps: (json['detailedSteps'] as List)
        .map((s) => RouteStep.fromJson(s))
        .toList(),
    legs: (json['legs'] as List)
        .map((s) => RouteStep.fromJson(s))
        .toList(),
    totalDistance: json['totalDistance']?.toDouble(),
    estimatedTime: json['estimatedTime'] != null
        ? Duration(minutes: json['estimatedTime'])
        : null,
    routeGeometry: json['routeGeometry'] != null
        ? (json['routeGeometry'] as List)
        .map((point) => (point as List).map((coord) => (coord as num).toDouble()).toList())
        .toList()
        : null,
    encodedPolyline: json['encodedPolyline'],
  );
}

class RouteStep {
  final String id;
  final int sequenceNumber;
  final DeliveryAddress address;
  final String? instructions;
  final double? distanceFromPrevious;
  final Duration? estimatedTravelTime;
  final String? notes;

  RouteStep({
    String? id,
    required this.sequenceNumber,
    required this.address,
    this.instructions,
    this.distanceFromPrevious,
    this.estimatedTravelTime,
    this.notes,
  }) : id = id ?? const Uuid().v4();
  
  RouteStep copyWith({
    int? sequenceNumber,
    DeliveryAddress? address,
    String? instructions,
    double? distanceFromPrevious,
    Duration? estimatedTravelTime,
    String? notes,
  }) {
    return RouteStep(
      id: id,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      address: address ?? this.address,
      instructions: instructions ?? this.instructions,
      distanceFromPrevious: distanceFromPrevious ?? this.distanceFromPrevious,
      estimatedTravelTime: estimatedTravelTime ?? this.estimatedTravelTime,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sequenceNumber': sequenceNumber,
    'address': address.toJson(),
    'instructions': instructions,
    'distanceFromPrevious': distanceFromPrevious,
    'estimatedTravelTime': estimatedTravelTime?.inMinutes,
    'notes': notes,
  };

  factory RouteStep.fromJson(Map<String, dynamic> json) => RouteStep(
    id: json['id'],
    sequenceNumber: json['sequenceNumber'] ?? 0,
    address: DeliveryAddress.fromJson(json['address']),
    instructions: json['instructions'],
    distanceFromPrevious: json['distanceFromPrevious']?.toDouble(),
    estimatedTravelTime: json['estimatedTime'] != null
        ? Duration(minutes: json['estimatedTime'])
        : null,
    notes: json['notes'],
  );
}
