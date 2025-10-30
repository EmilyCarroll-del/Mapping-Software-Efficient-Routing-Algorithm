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
}

