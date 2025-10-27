import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _addressesCollectionPath = 'addresses';
  final String _usersCollectionPath = 'users';

  // Get addresses assigned to a specific driver
  Stream<List<DeliveryAddress>> getDriverAssignedAddresses(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) {
              final data = doc.data();
              return DeliveryAddress.fromJson({
                'id': doc.id,
                ...data,
              });
            }).toList());
  }

  // Get completed addresses for a specific driver
  Stream<List<DeliveryAddress>> getDriverCompletedAddresses(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) {
              final data = doc.data();
              return DeliveryAddress.fromJson({
                'id': doc.id,
                ...data,
              });
            }).toList());
  }

  // Get in-progress addresses for a specific driver
  Stream<List<DeliveryAddress>> getDriverInProgressAddresses(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'in_progress')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) {
              final data = doc.data();
              return DeliveryAddress.fromJson({
                'id': doc.id,
                ...data,
              });
            }).toList());
  }

  // Update address status
  Future<void> updateAddressStatus(String addressId, String status) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'status': status,
    });
  }

  // Get total count of addresses for a driver
  Stream<int> getDriverAddressCount(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get count of completed addresses for a driver
  Stream<int> getDriverCompletedCount(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get count of in-progress addresses for a driver
  Stream<int> getDriverInProgressCount(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'in_progress')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
