import 'package:uuid/uuid.dart';
import 'delivery_address.dart';

enum RouteAlgorithm {
  dijkstra,
  prim,
  kruskal,
  fordBellman,
  nearestNeighbor,
}

class RouteOptimization {
  final String id;
  final String name;
  final List<DeliveryAddress> addresses;
  final RouteAlgorithm algorithm;
  final DateTime createdAt;
  final DateTime? completedAt;
  final List<RouteStep>? optimizedRoute;
  final double? totalDistance;
  final Duration? estimatedTime;

  RouteOptimization({
    String? id,
    required this.name,
    required this.addresses,
    required this.algorithm,
    DateTime? createdAt,
    this.completedAt,
    this.optimizedRoute,
    this.totalDistance,
    this.estimatedTime,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  bool get isCompleted => completedAt != null && optimizedRoute != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'addresses': addresses.map((a) => a.toJson()).toList(),
    'algorithm': algorithm.name,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'optimizedRoute': optimizedRoute?.map((s) => s.toJson()).toList(),
    'totalDistance': totalDistance,
    'estimatedTime': estimatedTime?.inMinutes,
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
    optimizedRoute: json['optimizedRoute'] != null
        ? (json['optimizedRoute'] as List)
            .map((s) => RouteStep.fromJson(s))
            .toList()
        : null,
    totalDistance: json['totalDistance']?.toDouble(),
    estimatedTime: json['estimatedTime'] != null
        ? Duration(minutes: json['estimatedTime'])
        : null,
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
    sequenceNumber: json['sequenceNumber'],
    address: DeliveryAddress.fromJson(json['address']),
    instructions: json['instructions'],
    distanceFromPrevious: json['distanceFromPrevious']?.toDouble(),
    estimatedTravelTime: json['estimatedTravelTime'] != null
        ? Duration(minutes: json['estimatedTravelTime'])
        : null,
    notes: json['notes'],
  );
}
