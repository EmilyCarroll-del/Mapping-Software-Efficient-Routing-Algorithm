import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:graph_go/main.dart';
import 'package:graph_go/screens/home_screen.dart';
import 'package:graph_go/providers/delivery_provider.dart';

import 'home_screen_test.mocks.dart';

@GenerateMocks([FirebaseAuth, User])
void main() {
  group('HomeScreen Widget Tests', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
    });

    Widget createTestWidget({bool isLoggedIn = false}) {
      return ChangeNotifierProvider(
        create: (context) => DeliveryProvider(),
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: '/login',
                builder: (context, state) => const Scaffold(
                  body: Text('Login Page'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('should show welcome screen for non-authenticated users', (WidgetTester tester) async {
      // Arrange
      when(mockAuth.currentUser).thenReturn(null);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: false));

      // Assert
      expect(find.text('Welcome to GraphGo'), findsOneWidget);
      expect(find.text('Your intelligent route optimization platform for efficient logistics management.'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Don\'t have an account? Sign Up'), findsOneWidget);
      expect(find.byIcon(Icons.local_shipping), findsOneWidget);
    });

    testWidgets('should show main interface for authenticated users', (WidgetTester tester) async {
      // Arrange
      when(mockUser.email).thenReturn('test@example.com');
      when(mockAuth.currentUser).thenReturn(mockUser);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: true));

      // Assert
      expect(find.text('GraphGo - Route Optimization'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('GraphGo Logistics'), findsOneWidget);
      expect(find.text('Delivery Addresses'), findsOneWidget);
      expect(find.text('0/100'), findsOneWidget);
      expect(find.text('Addresses'), findsOneWidget);
      expect(find.text('Optimize'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('should navigate to login when Get Started is tapped', (WidgetTester tester) async {
      // Arrange
      when(mockAuth.currentUser).thenReturn(null);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: false));
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Login Page'), findsOneWidget);
    });

    testWidgets('should navigate to signup when Sign Up is tapped', (WidgetTester tester) async {
      // Arrange
      when(mockAuth.currentUser).thenReturn(null);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: false));
      await tester.tap(find.text('Don\'t have an account? Sign Up'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Login Page'), findsOneWidget);
    });

    testWidgets('should show address count correctly', (WidgetTester tester) async {
      // Arrange
      when(mockUser.email).thenReturn('test@example.com');
      when(mockAuth.currentUser).thenReturn(mockUser);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: true));

      // Assert
      expect(find.text('0/100'), findsOneWidget);
      expect(find.text('Ready for route optimization'), findsNothing);
    });

    testWidgets('should disable optimize button when less than 2 addresses', (WidgetTester tester) async {
      // Arrange
      when(mockUser.email).thenReturn('test@example.com');
      when(mockAuth.currentUser).thenReturn(mockUser);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: true));

      // Assert
      final optimizeButton = find.widgetWithText(ElevatedButton, 'Optimize');
      expect(optimizeButton, findsOneWidget);
      
      final button = tester.widget<ElevatedButton>(optimizeButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('should show Google Maps widget for authenticated users', (WidgetTester tester) async {
      // Arrange
      when(mockUser.email).thenReturn('test@example.com');
      when(mockAuth.currentUser).thenReturn(mockUser);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: true));

      // Assert
      expect(find.byType(GoogleMap), findsOneWidget);
    });

    testWidgets('should show logout button for authenticated users', (WidgetTester tester) async {
      // Arrange
      when(mockUser.email).thenReturn('test@example.com');
      when(mockAuth.currentUser).thenReturn(mockUser);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: true));

      // Assert
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('should show login button for non-authenticated users', (WidgetTester tester) async {
      // Arrange
      when(mockAuth.currentUser).thenReturn(null);

      // Act
      await tester.pumpWidget(createTestWidget(isLoggedIn: false));

      // Assert
      expect(find.byIcon(Icons.login), findsOneWidget);
    });
  });
}
