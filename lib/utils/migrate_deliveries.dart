import 'package:cloud_firestore/cloud_firestore.dart';

/// Utility class to migrate accepted addresses to deliveries collection
/// This should be run once to move accepted addresses from 'addresses' to 'deliveries'
class DeliveryMigration {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Migrate all addresses that have been accepted (have a driverId) to the deliveries collection
  static Future<void> migrateAcceptedAddressesToDeliveries() async {
    try {
      print('🔄 Starting migration of accepted addresses to deliveries collection...');

      // Get all addresses that have been accepted (have a driverId)
      QuerySnapshot acceptedAddresses = await _db
          .collection('addresses')
          .where('driverId', isNull: false)
          .get();

      print('📦 Found ${acceptedAddresses.docs.length} accepted addresses to migrate');

      // Migrate each accepted address to the deliveries collection
      for (QueryDocumentSnapshot doc in acceptedAddresses.docs) {
        Map<String, dynamic> addressData = doc.data() as Map<String, dynamic>;
        
        // Add the address to the deliveries collection
        await _db.collection('deliveries').doc(doc.id).set({
          ...addressData,
          'migratedAt': FieldValue.serverTimestamp(),
          'originalCollection': 'addresses',
        });

        print('✅ Migrated delivery: ${addressData['fullAddress'] ?? 'Unknown address'}');
      }

      print('🎉 Migration completed successfully!');
      print('📊 Migrated ${acceptedAddresses.docs.length} addresses to deliveries collection');
      
    } catch (e) {
      print('❌ Error during migration: $e');
      rethrow;
    }
  }

  /// Check if deliveries collection exists and has data
  static Future<void> checkDeliveriesCollection() async {
    try {
      QuerySnapshot deliveries = await _db.collection('deliveries').limit(1).get();
      
      if (deliveries.docs.isEmpty) {
        print('📭 Deliveries collection is empty or does not exist');
        print('💡 Run migrateAcceptedAddressesToDeliveries() to populate it');
      } else {
        print('✅ Deliveries collection exists and has data');
        
        // Get total count
        QuerySnapshot totalDeliveries = await _db.collection('deliveries').get();
        print('📊 Total deliveries: ${totalDeliveries.docs.length}');
      }
    } catch (e) {
      print('❌ Error checking deliveries collection: $e');
    }
  }

  /// Remove migrated addresses from the original addresses collection
  /// WARNING: This will delete the original addresses that were migrated
  static Future<void> removeMigratedAddresses() async {
    try {
      print('⚠️  WARNING: This will remove migrated addresses from the original collection');
      print('🔄 Getting list of migrated addresses...');

      // Get all addresses that have been accepted (have a driverId)
      QuerySnapshot acceptedAddresses = await _db
          .collection('addresses')
          .where('driverId', isNull: false)
          .get();

      print('📦 Found ${acceptedAddresses.docs.length} addresses to remove from addresses collection');

      // Remove each accepted address from the addresses collection
      for (QueryDocumentSnapshot doc in acceptedAddresses.docs) {
        await _db.collection('addresses').doc(doc.id).delete();
        print('🗑️  Removed address: ${doc.id}');
      }

      print('🎉 Cleanup completed successfully!');
      print('📊 Removed ${acceptedAddresses.docs.length} addresses from addresses collection');
      
    } catch (e) {
      print('❌ Error during cleanup: $e');
      rethrow;
    }
  }
}
