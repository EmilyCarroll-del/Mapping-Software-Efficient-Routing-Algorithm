import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _addressesCollectionPath = 'addresses';
  final String _usersCollectionPath = 'users';

  // Get a stream of addresses for a specific user
  Stream<List<DeliveryAddress>> getAddresses(String userId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  // Get a stream of unassigned addresses
  Stream<List<DeliveryAddress>> getUnassignedAddresses(String userId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }


  // Add or update an address
  Future<void> saveAddress(DeliveryAddress address) {
    return _db.collection(_addressesCollectionPath).doc(address.id).set(address.toJson());
  }

  // Save a list of addresses from a CSV
  Future<void> saveAddressesFromCsv(List<DeliveryAddress> addresses) async {
    final batch = _db.batch();
    for (final address in addresses) {
      final docRef = _db.collection(_addressesCollectionPath).doc(address.id);
      batch.set(docRef, address.toJson());
    }
    await batch.commit();
  }

  // Delete an address
  Future<void> deleteAddress(String addressId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).delete();
  }

  // Get a stream of addresses for a specific driver
  Stream<List<DeliveryAddress>> getDriverDeliveries(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  // Update delivery status to accepted
  Future<void> updateDeliveryStatus(String addressId, String status) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'status': status,
    });
  }

  // Deny an assignment
  Future<void> denyAssignment(String addressId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'status': 'denied',
      'driverId': FieldValue.delete(),
    });
  }

  // Get all users
  Stream<List<UserModel>> getUsers() {
    return _db.collection(_usersCollectionPath).snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }

  // Get all drivers
  Stream<List<UserModel>> getDrivers() {
    return _db
        .collection(_usersCollectionPath)
        .where('role', isEqualTo: 'driver')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }

    // Get a stream of assigned addresses for a specific user
  Stream<List<DeliveryAddress>> getAssignedAddresses(String userId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['assigned', 'accepted'])
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  // Get a user by their ID
  Future<UserModel?> getUserById(String uid) async {
    final doc = await _db.collection(_usersCollectionPath).doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }
    return null;
  }

  // Assign a list of addresses to a list of drivers in a round-robin fashion
  Future<void> assignAddressesToDrivers(
      List<String> addressIds, List<String> driverIds) async {
    if (addressIds.isEmpty || driverIds.isEmpty) return;

    final batch = _db.batch();
    int driverIndex = 0;

    for (final addressId in addressIds) {
      final driverId = driverIds[driverIndex];
      final docRef = _db.collection(_addressesCollectionPath).doc(addressId);
      batch.update(docRef, {'driverId': driverId, 'status': 'assigned'});
      driverIndex = (driverIndex + 1) % driverIds.length;
    }

    await batch.commit();
  }

  // Unassign all addresses for a specific user
  Future<void> unassignAllAddresses(String userId) async {
    final addresses = await getAssignedAddresses(userId).first;
    final batch = _db.batch();

    for (final address in addresses) {
      final docRef = _db.collection(_addressesCollectionPath).doc(address.id);
      batch.update(docRef, {'driverId': FieldValue.delete(), 'status': 'pending'});
    }

    await batch.commit();
  }

  // Reassign a denied address
  Future<void> reassignAddress(String addressId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'status': 'pending',
      'driverId': FieldValue.delete(),
    });
  }


  // Assign a user the driver role
  Future<void> assignDriverRole(String uid) {
    return _db.collection(_usersCollectionPath).doc(uid).update({'role': 'driver'});
  }

  // Remove the driver role from a user
  Future<void> removeDriverRole(String uid) {
    return _db.collection(_usersCollectionPath).doc(uid).update({'role': FieldValue.delete()});
  }

  // Assign an address to a driver
  Future<void> assignAddressToDriver(String addressId, String driverId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'driverId': driverId,
      'status': 'assigned',
    });
  }
}
