import 'package:cloud_firestore/cloud_firestore.dart';

class Company {
  final String id;
  final String code;
  final String name;
  final String? description;
  final DateTime? createdAt;

  Company({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.createdAt,
  });

  factory Company.fromJson(Map<String, dynamic> json, String id) {
    return Company(
      id: id,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'description': description,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    };
  }
}

