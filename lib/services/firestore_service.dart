import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _addressesCollectionPath = 'addresses';
  final String _usersCollectionPath = 'users';
  final String _ordersCollectionPath = 'orders';

  // ADDRESS METHODS

  Stream<List<DeliveryAddress>> getAddresses(String userId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  Stream<List<DeliveryAddress>> getUnassignedAddresses(String userId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  Future<void> saveAddress(DeliveryAddress address) {
    return _db.collection(_addressesCollectionPath).doc(address.id).set(address.toJson());
  }

  Future<void> saveAddressesFromCsv(List<DeliveryAddress> addresses) async {
    final batch = _db.batch();
    for (final address in addresses) {
      final docRef = _db.collection(_addressesCollectionPath).doc(address.id);
      batch.set(docRef, address.toJson());
    }
    await batch.commit();
  }

  Future<void> deleteAddress(String addressId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).delete();
  }

  Stream<List<DeliveryAddress>> getDriverDeliveries(String driverId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  Future<void> updateDeliveryStatus(String addressId, String status) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'status': status,
    });
  }

  Future<void> denyAssignment(String addressId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'status': 'denied',
      'driverId': FieldValue.delete(),
    });
  }

  Stream<List<DeliveryAddress>> getAssignedAddresses(String userId) {
    return _db
        .collection(_addressesCollectionPath)
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['assigned', 'accepted', 'in_progress', 'denied'])
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => DeliveryAddress.fromJson(doc.data())).toList());
  }

  Future<void> reassignAddress(String addressId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'status': 'pending',
      'driverId': FieldValue.delete(),
    });
  }

  // ✅ NEW METHOD: Get completed deliveries for an admin
  Stream<List<DeliveryAddress>> getCompletedAddressesForAdmin(String adminUid) {
    return _db
        .collection(_addressesCollectionPath)
        .where('userId', isEqualTo: adminUid)
        .where('status', isEqualTo: 'completed')
    // .orderBy('createdAt', descending: true) // optional: uncomment if your collection has a createdAt field
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
      final data = doc.data();
      return DeliveryAddress.fromJson({
        'id': doc.id,
        ...data,
      });
    }).toList());
  }

  // USER & DRIVER METHODS

  Stream<List<UserModel>> getUsers() {
    return _db.collection(_usersCollectionPath).snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }

  Stream<List<UserModel>> getDrivers() {
    return _db
        .collection(_usersCollectionPath)
        .where('role', whereIn: ['driver', 'Driver'])
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }

  Stream<List<UserModel>> getFreelanceDrivers() {
    return _db
        .collection(_usersCollectionPath)
        .where('role', whereIn: ['driver', 'Driver'])
        .where('companyId', isEqualTo: null)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }

  Stream<List<UserModel>> getDriversByCompany(String companyId) {
    return _db
        .collection(_usersCollectionPath)
        .where('role', whereIn: ['driver', 'Driver'])
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _db.collection(_usersCollectionPath).doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }
    return null;
  }

  Future<void> assignDriverRole(String uid) {
    return _db.collection(_usersCollectionPath).doc(uid).update({'role': 'driver'});
  }

  Future<void> removeDriverRole(String uid) {
    return _db.collection(_usersCollectionPath).doc(uid).update({'role': FieldValue.delete()});
  }

  // ASSIGNMENT METHODS

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

  Future<void> unassignAllAddresses(String userId) async {
    final addresses = await getAssignedAddresses(userId).first;
    final batch = _db.batch();

    for (final address in addresses) {
      final docRef = _db.collection(_addressesCollectionPath).doc(address.id);
      batch.update(docRef, {'driverId': FieldValue.delete(), 'status': 'pending'});
    }

    await batch.commit();
  }

  Future<void> assignAddressToDriver(String addressId, String driverId) {
    return _db.collection(_addressesCollectionPath).doc(addressId).update({
      'driverId': driverId,
      'status': 'assigned',
    });
  }

  // DRIVER COMPLETED ADDRESSES
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

  // ALL DRIVERS COMPLETED ADDRESSES
  Future<List<DeliveryAddress>> getAllDriversCompletedAddresses(List<String> driverIds) async {
    if (driverIds.isEmpty) return [];

    try {
      final List<DeliveryAddress> allAddresses = [];

      final futures = driverIds.map((driverId) =>
          _db
              .collection(_addressesCollectionPath)
              .where('driverId', isEqualTo: driverId)
              .where('status', isEqualTo: 'completed')
              .get()
      );

      final results = await Future.wait(futures);

      for (final snapshot in results) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          try {
            allAddresses.add(DeliveryAddress.fromJson({
              'id': doc.id,
              ...data,
            }));
          } catch (e) {
            print('Error parsing address ${doc.id}: $e');
          }
        }
      }

      allAddresses.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return allAddresses;
    } catch (e) {
      print('Error fetching completed addresses: $e');
      return [];
    }
  }

  // ORDER METHODS

  Stream<List<OrderModel>> getOrders(String adminId) {
    return _db
        .collection(_ordersCollectionPath)
        .where('adminId', isEqualTo: adminId)
        .snapshots()
        .map((snapshot) {
      final orders =
      snapshot.docs.map((doc) => OrderModel.fromJson(doc.data())).toList();
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return orders;
    });
  }

  Future<void> createOrder({
    required String orderId,
    required String adminId,
    required DeliveryAddress pickUpAddress,
    required List<DeliveryAddress> dropOffAddresses,
  }) async {
    final reservedPickUp = pickUpAddress.copyWith(status: 'reserved');
    final reservedDropOffs =
    dropOffAddresses.map((a) => a.copyWith(status: 'reserved')).toList();

    final order = OrderModel(
      orderId: orderId,
      adminId: adminId,
      pickUpAddress: reservedPickUp,
      dropOffAddresses: reservedDropOffs,
      createdAt: Timestamp.now(),
      status: 'pending',
    );

    final batch = _db.batch();
    final orderRef = _db.collection(_ordersCollectionPath).doc(order.orderId);
    batch.set(orderRef, order.toJson());

    batch.update(
        _db.collection(_addressesCollectionPath).doc(pickUpAddress.id),
        {'status': 'reserved'});
    for (final address in dropOffAddresses) {
      batch.update(
          _db.collection(_addressesCollectionPath).doc(address.id),
          {'status': 'reserved'});
    }
    await batch.commit();
  }

  Future<void> deleteOrder(String orderId) async {
    final orderRef = _db.collection(_ordersCollectionPath).doc(orderId);
    await _db.runTransaction((transaction) async {
      final orderSnapshot = await transaction.get(orderRef);
      if (!orderSnapshot.exists) return;
      final order = OrderModel.fromJson(orderSnapshot.data()!);

      transaction.update(
          _db.collection(_addressesCollectionPath).doc(order.pickUpAddress.id),
          {'status': 'pending', 'driverId': FieldValue.delete()});
      for (final address in order.dropOffAddresses) {
        transaction.update(
            _db.collection(_addressesCollectionPath).doc(address.id),
            {'status': 'pending', 'driverId': FieldValue.delete()});
      }
      transaction.delete(orderRef);
    });
  }

  Future<bool> orderIdExists(String orderId) async {
    final doc = await _db.collection(_ordersCollectionPath).doc(orderId).get();
    return doc.exists;
  }

  Future<void> assignOrderToDrivers(String orderId, List<String> driverIds) async {
    final orderRef = _db.collection(_ordersCollectionPath).doc(orderId);
    await _db.runTransaction((transaction) async {
      final orderSnapshot = await transaction.get(orderRef);
      if (!orderSnapshot.exists) throw Exception("Order not found!");
      final order = OrderModel.fromJson(orderSnapshot.data()!);

      final newStatus = driverIds.isEmpty ? 'pending' : 'assigned';

      transaction.update(orderRef, {'driverIds': driverIds, 'status': newStatus});
      // TODO: Update addresses as well
    });
  }

  Future<void> unassignOrder(String orderId) async {
    return assignOrderToDrivers(orderId, []);
  }
}
