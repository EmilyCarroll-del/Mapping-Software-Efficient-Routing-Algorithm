import 'package:cloud_firestore/cloud_firestore.dart';
import 'company_service.dart';

/// Service for seeding companies with code ranges in Firestore
class CompanySeeder {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final CompanyService _companyService = CompanyService();

  /// Seed companies with predefined code ranges (5-digit codes: 10000-99999)
  /// 
  /// Creates/updates companies in Firestore:
  /// - Amazon: 10000-29999 (20,000 codes)
  /// - DHL: 30000-49999 (20,000 codes)
  /// - UPS: 50000-69999 (20,000 codes)
  /// - FedEx: 70000-89999 (20,000 codes)
  /// - Reserve: 90000-99999 (10,000 codes for future use)
  Future<void> seedCompanies() async {
    try {
      final companies = [
        {
          'name': 'Amazon',
          'code': '10000-29999',
          'codeRangeStart': 10000,
          'codeRangeEnd': 29999,
          'description': 'Amazon delivery services',
        },
        {
          'name': 'DHL',
          'code': '30000-49999',
          'codeRangeStart': 30000,
          'codeRangeEnd': 49999,
          'description': 'DHL Express delivery',
        },
        {
          'name': 'UPS',
          'code': '50000-69999',
          'codeRangeStart': 50000,
          'codeRangeEnd': 69999,
          'description': 'United Parcel Service',
        },
        {
          'name': 'FedEx',
          'code': '70000-89999',
          'codeRangeStart': 70000,
          'codeRangeEnd': 89999,
          'description': 'Federal Express delivery',
        },
      ];

      for (final companyData in companies) {
        // Check if company exists by name
        final snapshot = await _db
            .collection('companies')
            .where('name', isEqualTo: companyData['name'])
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          // Update existing company
          await snapshot.docs.first.reference.update({
            'code': companyData['code'],
            'codeRangeStart': companyData['codeRangeStart'],
            'codeRangeEnd': companyData['codeRangeEnd'],
            'description': companyData['description'],
          });
          print('Updated company: ${companyData['name']}');
        } else {
          // Create new company
          await _db.collection('companies').add({
            'name': companyData['name'],
            'code': companyData['code'],
            'codeRangeStart': companyData['codeRangeStart'],
            'codeRangeEnd': companyData['codeRangeEnd'],
            'description': companyData['description'],
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('Created company: ${companyData['name']}');
        }
      }

      print('Companies seeded successfully!');
    } catch (e) {
      print('Error seeding companies: $e');
      rethrow;
    }
  }
}

