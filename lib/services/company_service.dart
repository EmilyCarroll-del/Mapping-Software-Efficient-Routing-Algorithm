import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/company_model.dart';

class CompanyService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _companiesCollectionPath = 'companies';

  // Get all pre-created companies
  Future<List<Company>> getAllCompanies() async {
    try {
      final snapshot = await _db
          .collection(_companiesCollectionPath)
          .orderBy('name')
          .get();

      return snapshot.docs
          .map((doc) => Company.fromJson(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Error getting companies: $e');
      return [];
    }
  }

  // Stream all companies for real-time updates
  Stream<List<Company>> getAllCompaniesStream() {
    return _db
        .collection(_companiesCollectionPath)
        .orderBy('name')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Company.fromJson(doc.data(), doc.id))
            .toList());
  }

  // Get a specific company by its code
  Future<Company?> getCompanyByCode(String code) async {
    try {
      final snapshot = await _db
          .collection(_companiesCollectionPath)
          .where('code', isEqualTo: code.toUpperCase())
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      return Company.fromJson(snapshot.docs.first.data(), snapshot.docs.first.id);
    } catch (e) {
      print('Error getting company by code: $e');
      return null;
    }
  }

  // Create a new company (admin use - typically pre-created)
  Future<String?> createCompany({
    required String code,
    required String name,
    String? description,
  }) async {
    try {
      // Check if code already exists
      final existing = await getCompanyByCode(code);
      if (existing != null) {
        throw Exception('Company code already exists');
      }

      final docRef = await _db.collection(_companiesCollectionPath).add({
        'code': code.toUpperCase(),
        'name': name,
        'description': description,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return docRef.id;
    } catch (e) {
      print('Error creating company: $e');
      rethrow;
    }
  }

  /// Validate a company code format.
  /// 
  /// Company codes should be:
  /// - Non-empty
  /// - Typically 5 digits (but flexible for individual admins)
  /// 
  /// Returns: true if valid format, false otherwise
  bool isValidCompanyCodeFormat(String? code) {
    if (code == null || code.trim().isEmpty) {
      return false;
    }
    // Company codes should be alphanumeric and reasonable length (1-20 chars)
    final trimmed = code.trim();
    return trimmed.isNotEmpty && 
           trimmed.length <= 20 && 
           RegExp(r'^[A-Za-z0-9]+$').hasMatch(trimmed);
  }

  /// Check if a company code exists in the companies collection.
  /// 
  /// Note: Individual admins may use codes not in the companies collection.
  /// This method checks only pre-created companies.
  Future<bool> companyCodeExists(String code) async {
    try {
      final company = await getCompanyByCode(code);
      return company != null;
    } catch (e) {
      print('Error checking if company code exists: $e');
      return false;
    }
  }

  /// Validate company code for admin users.
  /// 
  /// Admins MUST have a companyCode (required).
  /// Returns error message if invalid, null if valid.
  String? validateAdminCompanyCode(String? companyCode) {
    if (companyCode == null || companyCode.trim().isEmpty) {
      return 'Admin users must provide a company code';
    }
    if (!isValidCompanyCodeFormat(companyCode)) {
      return 'Invalid company code format';
    }
    return null;
  }

  /// Validate company code for driver users.
  /// 
  /// Drivers have OPTIONAL companyCode.
  /// Returns error message if invalid, null if valid.
  String? validateDriverCompanyCode(String? companyCode) {
    // Drivers can have empty/null companyCode (freelancers)
    if (companyCode == null || companyCode.trim().isEmpty) {
      return null; // Valid - freelancer driver
    }
    // If provided, must be valid format
    if (!isValidCompanyCodeFormat(companyCode)) {
      return 'Invalid company code format';
    }
    return null;
  }

  /// Get company by code range (checks if code falls within any company's range)
  /// 
  /// Takes a numeric code and finds which company it belongs to based on range.
  /// Returns the company if code is within a valid range, null otherwise.
  Future<Company?> getCompanyByCodeRange(int codeValue) async {
    try {
      final companies = await getAllCompanies();
      
      for (final company in companies) {
        if (company.isCodeInRange(codeValue)) {
          return company;
        }
      }
      
      return null;
    } catch (e) {
      print('Error getting company by code range: $e');
      return null;
    }
  }

  /// Get company by code string (converts to int and checks range)
  /// 
  /// This method can handle both exact code matches and range-based lookups.
  Future<Company?> getCompanyByCodeOrRange(String code) async {
    try {
      // First try exact match (for backward compatibility)
      final exactMatch = await getCompanyByCode(code);
      if (exactMatch != null) {
        return exactMatch;
      }

      // Try to parse as integer and check ranges
      final codeValue = int.tryParse(code.trim());
      if (codeValue != null) {
        return await getCompanyByCodeRange(codeValue);
      }

      return null;
    } catch (e) {
      print('Error getting company by code or range: $e');
      return null;
    }
  }

  /// Generate a random code within a company's range
  /// 
  /// Returns a random integer code within the company's codeRangeStart to codeRangeEnd.
  /// Returns null if company doesn't have a valid range.
  Future<int?> generateCodeForCompanyAsync(String companyId) async {
    try {
      final companyDoc = await _db
          .collection(_companiesCollectionPath)
          .doc(companyId)
          .get();

      if (!companyDoc.exists) {
        return null;
      }

      final company = Company.fromJson(companyDoc.data()!, companyDoc.id);
      
      if (company.codeRangeStart == null || company.codeRangeEnd == null) {
        return null;
      }

      final random = Random();
      return company.codeRangeStart! + 
             random.nextInt(company.codeRangeEnd! - company.codeRangeStart! + 1);
    } catch (e) {
      print('Error generating code for company: $e');
      return null;
    }
  }

  /// Validate that a code is within a company's range
  /// 
  /// Returns error message if invalid, null if valid.
  Future<String?> validateCodeForCompany(String companyId, String code) async {
    try {
      final codeValue = int.tryParse(code.trim());
      if (codeValue == null) {
        return 'Code must be a valid number';
      }

      final companyDoc = await _db
          .collection(_companiesCollectionPath)
          .doc(companyId)
          .get();

      if (!companyDoc.exists) {
        return 'Company not found';
      }

      final company = Company.fromJson(companyDoc.data()!, companyDoc.id);
      
      if (company.codeRangeStart == null || company.codeRangeEnd == null) {
        return 'Company does not have a valid code range';
      }

      if (!company.isCodeInRange(codeValue)) {
        return 'Code must be between ${company.codeRangeStart} and ${company.codeRangeEnd}';
      }

      return null;
    } catch (e) {
      print('Error validating code for company: $e');
      return 'Error validating code: $e';
    }
  }
}

