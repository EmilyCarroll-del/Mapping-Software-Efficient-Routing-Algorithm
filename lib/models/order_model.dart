import 'package:cloud_firestore/cloud_firestore.dart';
import 'delivery_address.dart';

class OrderModel {
  final String orderId;
  final String adminId;
  final DeliveryAddress pickUpAddress;
  final List<DeliveryAddress> dropOffAddresses;
  final Timestamp createdAt;
  final String status;
  final List<String> driverIds;

  OrderModel({
    required this.orderId,
    required this.adminId,
    required this.pickUpAddress,
    required this.dropOffAddresses,
    required this.createdAt,
    this.status = 'pending',
    this.driverIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'adminId': adminId,
    'pickUpAddress': pickUpAddress.toJson(),
    'dropOffAddresses': dropOffAddresses.map((a) => a.toJson()).toList(),
    'createdAt': createdAt,
    'status': status,
    'driverIds': driverIds,
  };

  factory OrderModel.fromJson(Map<String, dynamic> json) => OrderModel(
    orderId: json['orderId'],
    adminId: json['adminId'],
    pickUpAddress: DeliveryAddress.fromJson(json['pickUpAddress']),
    dropOffAddresses: (json['dropOffAddresses'] as List)
        .map((a) => DeliveryAddress.fromJson(a))
        .toList(),
    createdAt: json['createdAt'],
    status: json['status'],
    driverIds: List<String>.from(json['driverIds'] ?? []),
  );
}
