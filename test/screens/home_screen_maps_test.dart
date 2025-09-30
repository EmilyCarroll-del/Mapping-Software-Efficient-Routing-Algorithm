import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:graph_go/screens/home_screen.dart';
import 'package:graph_go/providers/delivery_provider.dart';

// Generate mocks
@GenerateMocks([FirebaseAuth, User, DeliveryProvider])
import 'home_screen_maps_test.mocks.dart';

void main() {
  group('HomeScreen Maps Tests', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockDeliveryProvider mockDeliveryProvider;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockDeliveryProvider = MockDeliveryProvider();
    });

    testWidgets('HomeScreen displays Google Maps as primary interface', (WidgetTester tester) async {
      // Mock FirebaseAuth to return a user
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.email).thenReturn('test@example.com');
      when(mockDeliveryProvider.addressCount).thenReturn(0);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DeliveryProvider>(
            create: (context) => mockDeliveryProvider,
            child: const HomeScreen(),
          ),
        ),
      );

      // Should show Google Maps
      expect(find.byType(GoogleMap), findsOneWidget);
    });

    testWidgets('HomeScreen shows location status indicator', (WidgetTester tester) async {
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.email).thenReturn('test@example.com');
      when(mockDeliveryProvider.addressCount).thenReturn(0);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DeliveryProvider>(
            create: (context) => mockDeliveryProvider,
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show location status (Live/Offline)
      expect(find.text('Live'), findsOneWidget);
    });

    testWidgets('HomeScreen has current location button', (WidgetTester tester) async {
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.email).thenReturn('test@example.com');
      when(mockDeliveryProvider.addressCount).thenReturn(0);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DeliveryProvider>(
            create: (context) => mockDeliveryProvider,
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should have current location button
      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets('HomeScreen shows quick stats for logged-in users', (WidgetTester tester) async {
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.email).thenReturn('test@example.com');
      when(mockDeliveryProvider.addressCount).thenReturn(5);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DeliveryProvider>(
            create: (context) => mockDeliveryProvider,
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show quick stats
      expect(find.text('Addresses'), findsOneWidget);
      expect(find.text('Routes'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // Address count
    });

    testWidgets('HomeScreen shows action buttons for logged-in users', (WidgetTester tester) async {
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.email).thenReturn('test@example.com');
      when(mockDeliveryProvider.addressCount).thenReturn(0);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DeliveryProvider>(
            create: (context) => mockDeliveryProvider,
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show action buttons
      expect(find.text('Add Address'), findsOneWidget);
      expect(find.text('Optimize'), findsOneWidget);
    });

    testWidgets('HomeScreen shows login button for non-authenticated users', (WidgetTester tester) async {
      when(mockAuth.currentUser).thenReturn(null);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DeliveryProvider>(
            create: (context) => mockDeliveryProvider,
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show login button
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('HomeScreen has profile button for authenticated users', (WidgetTester tester) async {
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.email).thenReturn('test@example.com');
      when(mockDeliveryProvider.addressCount).thenReturn(0);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DeliveryProvider>(
            create: (context) => mockDeliveryProvider,
            child: const HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show profile button
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });
}
