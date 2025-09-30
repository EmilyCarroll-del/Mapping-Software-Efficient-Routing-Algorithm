import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:graph_go/screens/profile_screen.dart';
import 'package:graph_go/colors.dart';

// Generate mocks
@GenerateMocks([FirebaseAuth, User, FirebaseFirestore, FirebaseStorage, ImagePicker])
import 'profile_screen_test.mocks.dart';

void main() {
  group('ProfileScreen Tests', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockFirebaseFirestore mockFirestore;
    late MockFirebaseStorage mockStorage;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockFirestore = MockFirebaseFirestore();
      mockStorage = MockFirebaseStorage();
    });

    testWidgets('ProfileScreen displays loading indicator initially', (WidgetTester tester) async {
      // Mock FirebaseAuth to return a user
      when(mockAuth.currentUser).thenReturn(mockUser);
      when(mockUser.uid).thenReturn('test-uid');
      when(mockUser.email).thenReturn('test@example.com');
      when(mockUser.displayName).thenReturn('Test User');

      await tester.pumpWidget(
        MaterialApp(
          home: const ProfileScreen(),
        ),
      );

      // Initially should show loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('ProfileScreen shows profile information when loaded', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const ProfileScreen(),
        ),
      );

      // Wait for the widget to load
      await tester.pumpAndSettle();

      // Should show profile elements
      expect(find.text('Profile'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('ProfileScreen has edit functionality', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const ProfileScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Should have edit button
      expect(find.byIcon(Icons.edit), findsOneWidget);

      // Tap edit button
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();

      // Should show save and close buttons
      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('ProfileScreen shows route optimization stats', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const ProfileScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Should show stats section
      expect(find.text('Route Optimization Stats'), findsOneWidget);
      expect(find.text('Routes'), findsOneWidget);
      expect(find.text('Deliveries'), findsOneWidget);
      expect(find.text('Distance (km)'), findsOneWidget);
      expect(find.text('Efficiency'), findsOneWidget);
    });

    testWidgets('ProfileScreen has logout functionality', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const ProfileScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Should have logout button
      expect(find.text('Logout'), findsOneWidget);
    });
  });
}
