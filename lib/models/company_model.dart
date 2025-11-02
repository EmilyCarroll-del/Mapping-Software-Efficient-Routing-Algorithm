import 'package:cloud_firestore/cloud_firestore.dart';

class Company {
  final String id;
  final String code;
  final String name;
  final String? description;
  final DateTime? createdAt;
  final int? codeRangeStart; // Start of code range (e.g., 1000 for Amazon)
  final int? codeRangeEnd; // End of code range (e.g., 2999 for Amazon)

  Company({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.createdAt,
    this.codeRangeStart,
    this.codeRangeEnd,
  });

  factory Company.fromJson(Map<String, dynamic> json, String id) {
    return Company(
      id: id,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: (json['createdAt'] as Timestamp?)?.toDate(),
      codeRangeStart: json['codeRangeStart'] as int?,
      codeRangeEnd: json['codeRangeEnd'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'description': description,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (codeRangeStart != null) 'codeRangeStart': codeRangeStart,
      if (codeRangeEnd != null) 'codeRangeEnd': codeRangeEnd,
    };
  }

  /// Check if a code (as integer) falls within this company's range
  bool isCodeInRange(int codeValue) {
    if (codeRangeStart == null || codeRangeEnd == null) {
      return false;
    }
    return codeValue >= codeRangeStart! && codeValue <= codeRangeEnd!;
  }
}

