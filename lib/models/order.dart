import 'package:cloud_firestore/cloud_firestore.dart';
import 'delivery_address.dart';

class Order {
  final String id;
  final String sourceCollection; // 'addresses' or 'orders'
  final DeliveryAddress pickupAddress;
  final List<DeliveryAddress> dropOffAddresses;
  final String? notes;
  final String status;
  final String? driverId;
  final List<String>? driverIds;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Order({
    required this.id,
    required this.sourceCollection,
    required this.pickupAddress,
    required this.dropOffAddresses,
    this.notes,
    required this.status,
    this.driverId,
    this.driverIds,
    required this.createdAt,
    this.updatedAt,
  });

  static DateTime _parseDate(dynamic date) {
    if (date == null) return DateTime.now();
    if (date is Timestamp) {
      return date.toDate();
    } else if (date is String) {
      return DateTime.parse(date);
    }
    return DateTime.now();
  }

  factory Order.fromAddressDoc(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Order(
      id: doc.id,
      sourceCollection: 'addresses',
      pickupAddress: DeliveryAddress.fromJson(data),
      dropOffAddresses: [],
      notes: data['notes'],
      status: data['status'] ?? 'assigned',
      driverId: data['driverId'],
      driverIds: null,
      createdAt: _parseDate(data['createdAt']),
      updatedAt: data['updatedAt'] != null ? _parseDate(data['updatedAt']) : null,
    );
  }

  factory Order.fromOrderDoc(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    var dropOffs = <DeliveryAddress>[];
    if (data['dropOffAddresses'] != null && data['dropOffAddresses'] is List) {
      for (var item in (data['dropOffAddresses'] as List<dynamic>)) {
        if (item is Map<String, dynamic>) {
          dropOffs.add(DeliveryAddress.fromJson(item));
        }
      }
    }

    final pickupData = data['pickUpAddress'] as Map<String, dynamic>?; // Corrected field name

    return Order(
      id: doc.id,
      sourceCollection: 'orders',
      pickupAddress: pickupData != null
          ? DeliveryAddress.fromJson(pickupData)
          : DeliveryAddress(streetAddress: 'Unknown Pickup', city: '', state: '', zipCode: ''),
      dropOffAddresses: dropOffs,
      notes: data['notes'],
      status: data['status'] ?? 'assigned',
      driverId: null,
      driverIds: List<String>.from(data['driverIds'] ?? []),
      createdAt: _parseDate(data['createdAt']),
      updatedAt: data['updatedAt'] != null ? _parseDate(data['updatedAt']) : null,
    );
  }
}
