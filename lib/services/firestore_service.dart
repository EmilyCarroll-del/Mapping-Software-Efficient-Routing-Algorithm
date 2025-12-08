import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_address.dart';
import '../models/order.dart' as app_order;

/// Service for managing Firestore operations related to deliveries and drivers.
/// 
/// COMPANY CODE SYSTEM - PRIMARY USER LINKING METHODOLOGY
/// 
/// Company codes are the PRIMARY way to identify and link users:
/// 
/// ADMIN USERS (Web App Only):
///   - Company Admins: Work for big delivery companies (FedEx, DHL, UPS, Amazon)
///     * MUST have companyCode (required)
///     * Multiple admins can share the same companyCode
///   - Individual Admins: Freelancers looking for truck drivers
///     * MUST have companyCode (required)
///     * Each individual admin has their own unique companyCode
/// 
/// DRIVER USERS (Mobile App Only):
///   - Company Drivers: Have companyCode → linked to company via matching code
///     * Can only work with admins who have the same companyCode
///   - Freelance Drivers: No companyCode (null/empty) → can work with any admin
/// 
/// ORDER ASSIGNMENT LOGIC (for web app implementation):
/// - Company drivers (with companyCode): Only receive orders from admins
///   with the same companyCode
/// - Freelance drivers (no companyCode): Can receive orders from any admin
/// - All admins MUST have a companyCode (enforced during web app signup)
/// 
/// When assigning orders in the web app, filter available drivers based on:
/// 1. Admin has companyCode (required) → show only drivers with matching companyCode
/// 2. Also show freelance drivers (no companyCode) so admins can assign to them too
/// 3. Filter out drivers who are already assigned/in-progress (as needed)
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _deliveriesCollectionPath = 'deliveries';
  final String _usersCollectionPath = 'users';

  // NEW: orders collection for multi-stop / pickup+dropoff orders
  final String _ordersCollectionPath = 'orders';

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

  // Get completed orders for a specific driver
  // Queries both 'orders' and 'addresses' collections
  Stream<List<app_order.Order>> getDriverCompletedAddresses(String driverId) {
    print('🔍 Route History: Querying completed orders for driver: $driverId');
    
    final controller = StreamController<List<app_order.Order>>();
    List<app_order.Order> ordersList = [];
    List<app_order.Order> addressesList = [];
    bool ordersReady = false;
    bool addressesReady = false;

    void emitCombined() {
      if (ordersReady && addressesReady) {
        final allOrders = <app_order.Order>[...ordersList, ...addressesList];
        
        // Sort by completedAt if available, otherwise by updatedAt or createdAt
        allOrders.sort((a, b) {
          final aDate = a.updatedAt ?? a.createdAt;
          final bDate = b.updatedAt ?? b.createdAt;
          return bDate.compareTo(aDate); // Descending (newest first)
        });
        
        print('✅ Route History: Returning ${allOrders.length} total completed orders (${ordersList.length} from orders, ${addressesList.length} from addresses)');
        controller.add(allOrders);
      }
    }

    // Query orders collection
    final ordersSubscription = _db
        .collection('orders')
        .where('driverIds', arrayContains: driverId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen(
          (snapshot) {
            print('📦 Route History: Found ${snapshot.docs.length} completed orders in "orders" collection');
            try {
              ordersList = snapshot.docs.map((doc) {
                try {
                  return app_order.Order.fromOrderDoc(doc);
                } catch (e) {
                  print('❌ Route History: Error parsing order doc ${doc.id}: $e');
                  return null;
                }
              }).whereType<app_order.Order>().toList();
              ordersReady = true;
              emitCombined();
            } catch (e) {
              print('❌ Route History: Error processing orders: $e');
              ordersList = [];
              ordersReady = true;
              emitCombined();
            }
          },
          onError: (error) {
            print('❌ Route History: Error querying orders collection: $error');
            ordersList = [];
            ordersReady = true;
            emitCombined();
          },
        );

    // Query addresses collection
    final addressesSubscription = _db
        .collection('addresses')
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'completed')
        .snapshots()
        .listen(
          (snapshot) {
            print('📍 Route History: Found ${snapshot.docs.length} completed addresses in "addresses" collection');
            try {
              addressesList = snapshot.docs.map((doc) {
                try {
                  return app_order.Order.fromAddressDoc(doc);
                } catch (e) {
                  print('❌ Route History: Error parsing address doc ${doc.id}: $e');
                  return null;
                }
              }).whereType<app_order.Order>().toList();
              addressesReady = true;
              emitCombined();
            } catch (e) {
              print('❌ Route History: Error processing addresses: $e');
              addressesList = [];
              addressesReady = true;
              emitCombined();
            }
          },
          onError: (error) {
            print('❌ Route History: Error querying addresses collection: $error');
            addressesList = [];
            addressesReady = true;
            emitCombined();
          },
        );

    // Clean up subscriptions when stream is cancelled or closed
    controller.onCancel = () {
      ordersSubscription.cancel();
      addressesSubscription.cancel();
    };

    // Handle stream close
    controller.onListen = () {
      // Stream is being listened to, subscriptions are already active
    };

    return controller.stream;
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

  /// Get available drivers for an admin based on company code linking rules.
  /// 
  /// Company Code Linking Rules:
  /// - Company drivers (with companyCode): Only visible to admins with matching companyCode
  /// - Freelance drivers (no companyCode): Visible to all admins
  /// 
  /// Args:
  ///   - adminCompanyCode: The company code of the admin (required)
  /// 
  /// Returns: Stream of user documents that represent available drivers
  Stream<List<Map<String, dynamic>>> getAvailableDriversForAdmin(String adminCompanyCode) {
    // Get all drivers
    // Note: Firestore doesn't support OR queries directly, so we need to:
    // 1. Get drivers with matching companyCode
    // 2. Get freelance drivers (no companyCode)
    // 3. Combine and filter client-side or use multiple queries
    
    return _db
        .collection(_usersCollectionPath)
        .where('userType', isEqualTo: 'driver')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .where((doc) {
            final data = doc.data();
            final driverCompanyCode = data['companyCode'] as String?;
            
            // Show drivers with matching companyCode OR freelance drivers (no code)
            return driverCompanyCode == null || 
                   driverCompanyCode.isEmpty || 
                   driverCompanyCode == adminCompanyCode;
          })
          .map((doc) => {
            'id': doc.id,
            ...doc.data(),
          })
          .toList();
    });
  }

  /// Get drivers linked to a specific company code.
  /// 
  /// Returns all drivers (both company and freelance) that can work with the given company code.
  Future<List<Map<String, dynamic>>> getDriversByCompanyCode(String companyCode) async {
    try {
      // Get company drivers with matching code
      final companyDrivers = await _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'driver')
          .where('companyCode', isEqualTo: companyCode)
          .get();

      // Get freelance drivers (no companyCode)
      final allDrivers = await _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'driver')
          .get();

      final freelanceDrivers = allDrivers.docs
          .where((doc) {
            final data = doc.data();
            final code = data['companyCode'] as String?;
            return code == null || code.isEmpty;
          })
          .toList();

      // Combine results
      final allAvailableDrivers = [
        ...companyDrivers.docs,
        ...freelanceDrivers,
      ];

      return allAvailableDrivers.map((doc) => {
        'id': doc.id,
        ...doc.data(),
      }).toList();
    } catch (e) {
      print('Error getting drivers by company code: $e');
      return [];
    }
  }

  /// Get admins that a driver can communicate/work with based on company code.
  /// 
  /// Rules:
  /// - Company drivers (with companyCode): Can only see admins with matching companyCode
  /// - Freelance drivers (no companyCode): Can see all admins
  /// 
  /// Args:
  ///   - driverCompanyCode: The company code of the driver (null/empty for freelancers)
  /// 
  /// Returns: Stream of admin user documents
  Stream<List<Map<String, dynamic>>> getAvailableAdminsForDriver(String? driverCompanyCode) {
    if (driverCompanyCode == null || driverCompanyCode.isEmpty) {
      // Freelance drivers can see all admins
      return _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'admin')
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
              .toList());
    } else {
      // Company drivers can only see admins with matching companyCode
      return _db
          .collection(_usersCollectionPath)
          .where('userType', isEqualTo: 'admin')
          .where('companyCode', isEqualTo: driverCompanyCode)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
              .toList());
    }
  }

  /// Check if a driver and admin can work together based on company codes.
  /// 
  /// Returns true if:
  /// - Driver is freelance (no companyCode) → can work with any admin
  /// - Driver has companyCode matching admin's companyCode
  bool canDriverWorkWithAdmin(String? driverCompanyCode, String adminCompanyCode) {
    if (driverCompanyCode == null || driverCompanyCode.isEmpty) {
      // Freelance driver can work with any admin
      return true;
    }
    // Company driver can only work with matching company admin
    return driverCompanyCode == adminCompanyCode;
  }

  // ---------------------------------------------------------------------------
  // NEW: ORDER ASSIGNMENT + NOTIFICATIONS FOR MULTI-STOP ORDERS
  // ---------------------------------------------------------------------------

  /// Assigns an order (from the `orders` collection) to one or more drivers.
  ///
  /// - Updates `driverIds` and `status` on the order document.
  /// - Detects which drivers are *newly* assigned (vs previously assigned).
  /// - For each newly assigned driver, creates a "New Order Assigned"
  ///   notification in the `notifications` collection.
  ///
  /// Assumes each order document has:
  ///   - `driverIds`: List<String>
  ///   - `status`: String
  ///   - `adminId`: String (creator/admin)
  ///   - `pickUpAddress`: Map with `streetAddress`, `city`, `state`, `zipCode`
  Future<void> assignOrderToDrivers(
      String orderId, List<String> driverIds) async {
    final orderRef = _db.collection(_ordersCollectionPath).doc(orderId);

    List<String> newlyAssignedDriverIds = [];
    String pickupSummary = '';
    String adminId = '';

    // 1) Transaction: update order + compute newly assigned drivers
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      if (!snapshot.exists) {
        throw Exception('Order not found');
      }

      final data = snapshot.data() as Map<String, dynamic>;

      final previousDriverIds = List<String>.from(
          (data['driverIds'] ?? const <dynamic>[]) as List<dynamic>);

      // drivers that were not previously assigned
      newlyAssignedDriverIds = driverIds
          .where((id) => !previousDriverIds.contains(id))
          .toList();

      // Build pickup address summary string for notification message
      final pickup =
      Map<String, dynamic>.from(data['pickUpAddress'] ?? const {});
      final street = (pickup['streetAddress'] ?? '').toString();
      final city = (pickup['city'] ?? '').toString();
      final state = (pickup['state'] ?? '').toString();
      final zip = (pickup['zipCode'] ?? '').toString();

      pickupSummary = [
        street,
        if (city.isNotEmpty) city,
        if (state.isNotEmpty) state,
        if (zip.isNotEmpty) zip,
      ].where((part) => part.isNotEmpty).join(', ');

      adminId = (data['adminId'] ?? '').toString();

      final newStatus = driverIds.isEmpty ? 'pending' : 'assigned';

      transaction.update(orderRef, {
        'driverIds': driverIds,
        'status': newStatus,
      });
    });

    // 2) Create notifications for newly assigned drivers
    if (newlyAssignedDriverIds.isEmpty) return;

    final message = pickupSummary.isNotEmpty
        ? 'You have been assigned a new order: $pickupSummary'
        : 'You have been assigned a new order.';

    for (final driverId in newlyAssignedDriverIds) {
      await _db.collection('notifications').add({
        'userId': driverId,
        'type': 'order', // used by "Orders" tab filter
        'title': 'New Order Assigned',
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'actionType': 'view_order',
        'actionData': {
          'orderId': orderId,
        },
        'metadata': {
          'adminId': adminId,
        },
      });
    }
  }
}
