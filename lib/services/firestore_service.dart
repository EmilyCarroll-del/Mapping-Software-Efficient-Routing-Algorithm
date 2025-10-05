import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collectionPath = 'addresses';

  // Get a stream of addresses for a specific user
  Stream<List<DeliveryAddress>> getAddresses(String userId) {
    return _db
        .collection(_collectionPath)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  // Add or update an address
  Future<void> saveAddress(DeliveryAddress address) {
    return _db.collection(_collectionPath).doc(address.id).set(address.toJson());
  }

  // Save a list of addresses from a CSV
  Future<void> saveAddressesFromCsv(List<DeliveryAddress> addresses) async {
    final batch = _db.batch();
    for (final address in addresses) {
      final docRef = _db.collection(_collectionPath).doc(address.id);
      batch.set(docRef, address.toJson());
    }
    await batch.commit();
  }

  // Delete an address
  Future<void> deleteAddress(String addressId) {
    return _db.collection(_collectionPath).doc(addressId).delete();
  }
}
