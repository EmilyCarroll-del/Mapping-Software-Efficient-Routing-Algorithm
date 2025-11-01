import 'package:cloud_firestore/cloud_firestore.dart';

/// User model representing both admin and driver users in the system.
/// 
/// Company Code System:
/// - Company codes are the PRIMARY way to identify and link users
/// - Admins: MUST have companyCode (required)
///   - Company Admins: Share companyCode with other admins (e.g., FedEx, DHL)
///   - Individual Admins: Have unique companyCode (freelancers looking for drivers)
/// - Drivers: OPTIONAL companyCode
///   - Company Drivers: Have companyCode → linked to company via matching code
///   - Freelance Drivers: No companyCode → can work with any admin
class UserModel {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? bio;
  final String? profileImageUrl;
  
  /// User type: 'admin' (web app only) or 'driver' (mobile app only)
  final String userType;
  
  /// Optional admin type: 'company_admin' or 'individual_admin'
  /// Only applicable when userType is 'admin'
  final String? adminType;
  
  /// Company code - PRIMARY identifier for linking users
  /// - Admins: REQUIRED (identifies company or individual admin)
  /// - Drivers: OPTIONAL (links driver to company; null/empty = freelancer)
  final String? companyCode;
  
  /// Company name (display only, for convenience)
  final String? company;
  
  final String provider; // 'email' or 'google'
  final DateTime? createdAt;
  final DateTime? lastSignIn;
  final String role; // 'Admin' or 'Driver'

  UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.bio,
    this.profileImageUrl,
    required this.userType,
    this.adminType,
    this.companyCode,
    this.company,
    required this.provider,
    this.createdAt,
    this.lastSignIn,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, String id) {
    return UserModel(
      id: id,
      firstName: json['first_name'] as String? ?? json['name']?.toString().split(' ').first ?? '',
      lastName: json['last_name'] as String? ?? (json['name']?.toString().contains(' ') 
          ? json['name'].toString().split(' ').skip(1).join(' ') 
          : ''),
      email: json['email'] as String,
      phone: json['phone'] as String?,
      bio: json['bio'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      userType: json['userType'] as String? ?? 'driver',
      adminType: json['adminType'] as String?,
      companyCode: json['companyCode'] as String?,
      company: json['company'] as String?,
      provider: json['provider'] as String? ?? 'email',
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? 
                 (json['createdAt'] as Timestamp?)?.toDate(),
      lastSignIn: (json['last_sign_in'] as Timestamp?)?.toDate(),
      role: json['role'] as String? ?? 'Driver',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      if (phone != null) 'phone': phone,
      if (bio != null) 'bio': bio,
      if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      'userType': userType,
      if (adminType != null) 'adminType': adminType,
      if (companyCode != null && companyCode!.isNotEmpty) 'companyCode': companyCode,
      if (company != null) 'company': company,
      'provider': provider,
      if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
      if (lastSignIn != null) 'last_sign_in': Timestamp.fromDate(lastSignIn!),
      'role': role,
    };
  }

  /// Check if user is a company driver (has companyCode)
  bool get isCompanyDriver => userType == 'driver' && companyCode != null && companyCode!.isNotEmpty;

  /// Check if user is a freelance driver (no companyCode)
  bool get isFreelanceDriver => userType == 'driver' && (companyCode == null || companyCode!.isEmpty);

  /// Check if user is a company admin
  bool get isCompanyAdmin => userType == 'admin' && adminType == 'company_admin';

  /// Check if user is an individual admin
  bool get isIndividualAdmin => userType == 'admin' && adminType == 'individual_admin';

  /// Check if user has a company code (non-empty)
  bool get hasCompanyCode => companyCode != null && companyCode!.isNotEmpty;

  /// Validate company code requirement based on user type
  /// Returns error message if invalid, null if valid
  String? validateCompanyCode() {
    if (userType == 'admin') {
      // Admins MUST have companyCode
      if (companyCode == null || companyCode!.trim().isEmpty) {
        return 'Admin users must have a company code';
      }
    }
    // Drivers can have optional companyCode
    return null;
  }
}

