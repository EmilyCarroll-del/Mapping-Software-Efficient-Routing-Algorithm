import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _deliveriesCollectionPath = 'deliveries';
  final String _usersCollectionPath = 'users';

  // Get deliveries assigned to a specific driver
  Stream<List<DeliveryAddress>> getDriverAssignedAddresses(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
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

  // Get completed deliveries for a specific driver
  Stream<List<DeliveryAddress>> getDriverCompletedAddresses(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
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

  // Get in-progress deliveries for a specific driver
  Stream<List<DeliveryAddress>> getDriverInProgressAddresses(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
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

  // Update delivery status
  Future<void> updateAddressStatus(String addressId, String status) {
    return _db.collection(_deliveriesCollectionPath).doc(addressId).update({
      'status': status,
    });
  }

  // Get total count of deliveries for a driver
  Stream<int> getDriverAddressCount(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get count of completed deliveries for a driver
  Stream<int> getDriverCompletedCount(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Get count of in-progress deliveries for a driver
  Stream<int> getDriverInProgressCount(String driverId) {
    return _db
        .collection(_deliveriesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'in_progress')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
