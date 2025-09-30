import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:graph_go/providers/delivery_provider.dart';
import 'package:graph_go/models/delivery_address.dart';
import 'package:graph_go/models/route_optimization.dart';
import 'package:graph_go/services/geocoding_service.dart';
import 'package:graph_go/services/routing_algorithms.dart';

import 'delivery_provider_test.mocks.dart';

@GenerateMocks([
  FirebaseAuth,
  User,
  FirebaseFirestore,
  CollectionReference,
  DocumentReference,
  QuerySnapshot,
  QueryDocumentSnapshot,
  GeocodingService,
])
void main() {
  group('DeliveryProvider Tests', () {
    late DeliveryProvider provider;
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockFirebaseFirestore mockFirestore;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockFirestore = MockFirebaseFirestore();
      
      provider = DeliveryProvider();
    });

    group('Initialization', () {
      test('should initialize with empty state', () {
        expect(provider.addresses, isEmpty);
        expect(provider.routeOptimizations, isEmpty);
        expect(provider.isLoading, false);
        expect(provider.error, null);
        expect(provider.hasAddresses, false);
        expect(provider.addressCount, 0);
        expect(provider.canAddMoreAddresses, true);
      });
    });

    group('Address Management', () {
      test('should add address successfully', () async {
        // Arrange
        final address = DeliveryAddress(
          id: 'test-id',
          fullAddress: '123 Test St, Test City',
          latitude: 40.7128,
          longitude: -74.0060,
        );

        // Act
        await provider.addAddress(address);

        // Assert
        expect(provider.addresses.length, 1);
        expect(provider.addresses.first.id, 'test-id');
        expect(provider.error, null);
      });

      test('should not add more than 100 addresses', () async {
        // Arrange
        for (int i = 0; i < 100; i++) {
          final address = DeliveryAddress(
            id: 'test-id-$i',
            fullAddress: '123 Test St $i, Test City',
            latitude: 40.7128,
            longitude: -74.0060,
          );
          await provider.addAddress(address);
        }

        final extraAddress = DeliveryAddress(
          id: 'extra-id',
          fullAddress: '123 Extra St, Test City',
          latitude: 40.7128,
          longitude: -74.0060,
        );

        // Act
        await provider.addAddress(extraAddress);

        // Assert
        expect(provider.addressCount, 100);
        expect(provider.error, 'Maximum of 100 addresses allowed');
        expect(provider.canAddMoreAddresses, false);
      });

      test('should update address successfully', () async {
        // Arrange
        final originalAddress = DeliveryAddress(
          id: 'test-id',
          fullAddress: '123 Test St, Test City',
          latitude: 40.7128,
          longitude: -74.0060,
        );
        await provider.addAddress(originalAddress);

        final updatedAddress = DeliveryAddress(
          id: 'test-id',
          fullAddress: '456 Updated St, Updated City',
          latitude: 41.7128,
          longitude: -75.0060,
        );

        // Act
        await provider.updateAddress(updatedAddress);

        // Assert
        expect(provider.addresses.length, 1);
        expect(provider.addresses.first.fullAddress, '456 Updated St, Updated City');
        expect(provider.error, null);
      });

      test('should remove address successfully', () async {
        // Arrange
        final address = DeliveryAddress(
          id: 'test-id',
          fullAddress: '123 Test St, Test City',
          latitude: 40.7128,
          longitude: -74.0060,
        );
        await provider.addAddress(address);

        // Act
        await provider.removeAddress('test-id');

        // Assert
        expect(provider.addresses, isEmpty);
        expect(provider.error, null);
      });
    });

    group('Route Optimization', () {
      setUp(() async {
        // Add test addresses
        final address1 = DeliveryAddress(
          id: 'addr1',
          fullAddress: '123 First St, Test City',
          latitude: 40.7128,
          longitude: -74.0060,
        );
        final address2 = DeliveryAddress(
          id: 'addr2',
          fullAddress: '456 Second St, Test City',
          latitude: 40.7589,
          longitude: -73.9851,
        );
        final address3 = DeliveryAddress(
          id: 'addr3',
          fullAddress: '789 Third St, Test City',
          latitude: 40.7505,
          longitude: -73.9934,
        );

        await provider.addAddress(address1);
        await provider.addAddress(address2);
        await provider.addAddress(address3);
      });

      test('should optimize route with Dijkstra algorithm', () async {
        // Act
        final result = await provider.optimizeRoute(
          name: 'Test Route',
          algorithm: RouteAlgorithm.dijkstra,
        );

        // Assert
        expect(result.name, 'Test Route');
        expect(result.algorithm, RouteAlgorithm.dijkstra);
        expect(result.addresses.length, 3);
        expect(result.optimizedRoute.length, 3);
        expect(result.totalDistance, greaterThan(0));
        expect(result.estimatedTime.inMinutes, greaterThan(0));
      });

      test('should optimize route with Nearest Neighbor algorithm', () async {
        // Act
        final result = await provider.optimizeRoute(
          name: 'NN Route',
          algorithm: RouteAlgorithm.nearestNeighbor,
        );

        // Assert
        expect(result.name, 'NN Route');
        expect(result.algorithm, RouteAlgorithm.nearestNeighbor);
        expect(result.addresses.length, 3);
        expect(result.optimizedRoute.length, 3);
      });

      test('should throw exception when no addresses available', () async {
        // Arrange
        provider = DeliveryProvider(); // Fresh provider with no addresses

        // Act & Assert
        expect(
          () => provider.optimizeRoute(
            name: 'Empty Route',
            algorithm: RouteAlgorithm.dijkstra,
          ),
          throwsException,
        );
      });

      test('should delete route optimization successfully', () async {
        // Arrange
        final result = await provider.optimizeRoute(
          name: 'Test Route',
          algorithm: RouteAlgorithm.dijkstra,
        );
        final routeId = result.id;

        // Act
        await provider.deleteRouteOptimization(routeId);

        // Assert
        expect(provider.routeOptimizations, isEmpty);
        expect(provider.error, null);
      });
    });

    group('Error Handling', () {
      test('should handle geocoding errors gracefully', () async {
        // Arrange
        final invalidAddress = DeliveryAddress(
          id: 'invalid-id',
          fullAddress: 'Invalid Address That Cannot Be Geocoded',
        );

        // Act
        await provider.addAddress(invalidAddress);

        // Assert
        expect(provider.error, isNotNull);
        expect(provider.error, contains('Failed to add address'));
      });
    });

    group('Loading States', () {
      test('should set loading state during operations', () async {
        // Arrange
        final address = DeliveryAddress(
          id: 'test-id',
          fullAddress: '123 Test St, Test City',
          latitude: 40.7128,
          longitude: -74.0060,
        );

        // Act
        final future = provider.addAddress(address);
        
        // Assert - loading should be true during operation
        expect(provider.isLoading, true);
        
        await future;
        
        // Assert - loading should be false after operation
        expect(provider.isLoading, false);
      });
    });
  });
}
