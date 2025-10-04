import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collectionPath = 'addresses';

  // Get a stream of all addresses
  Stream<List<DeliveryAddress>> getAddresses() {
    return _db.collection(_collectionPath).snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  // Add or update an address
  Future<void> saveAddress(DeliveryAddress address) {
    return _db.collection(_collectionPath).doc(address.id).set(address.toJson());
  }

  // Delete an address
  Future<void> deleteAddress(String addressId) {
    return _db.collection(_collectionPath).doc(addressId).delete();
  }
}
