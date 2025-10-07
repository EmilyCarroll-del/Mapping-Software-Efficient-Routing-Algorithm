import 'package:uuid/uuid.dart';

class DeliveryAddress {
  final String id;
  final String userId;
  final String streetAddress;
  final String city;
  final String state;
  final String zipCode;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final DateTime createdAt;
  final String? driverId;
  final String status;

  DeliveryAddress({
    String? id,
    required this.userId,
    required this.streetAddress,
    required this.city,
    required this.state,
    required this.zipCode,
    this.latitude,
    this.longitude,
    this.notes,
    DateTime? createdAt,
    this.driverId,
    this.status = 'pending',
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  String get fullAddress => '$streetAddress, $city, $state $zipCode';

  bool get hasCoordinates => latitude != null && longitude != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'streetAddress': streetAddress,
    'city': city,
    'state': state,
    'zipCode': zipCode,
    'latitude': latitude,
    'longitude': longitude,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'driverId': driverId,
    'status': status,
  };

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) => DeliveryAddress(
    id: json['id'],
    userId: json['userId'],
    streetAddress: json['streetAddress'],
    city: json['city'],
    state: json['state'],
    zipCode: json['zipCode'],
    latitude: json['latitude']?.toDouble(),
    longitude: json['longitude']?.toDouble(),
    notes: json['notes'],
    createdAt: DateTime.parse(json['createdAt']),
    driverId: json['driverId'],
    status: json['status'] ?? 'pending',
  );

  DeliveryAddress copyWith({
    String? userId,
    String? streetAddress,
    String? city,
    String? state,
    String? zipCode,
    double? latitude,
    double? longitude,
    String? notes,
    String? driverId,
    String? status,
  }) => DeliveryAddress(
    id: id,
    userId: userId ?? this.userId,
    streetAddress: streetAddress ?? this.streetAddress,
    city: city ?? this.city,
    state: state ?? this.state,
    zipCode: zipCode ?? this.zipCode,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    notes: notes ?? this.notes,
    createdAt: createdAt,
    driverId: driverId ?? this.driverId,
    status: status ?? this.status,
  );
}
