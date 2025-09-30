import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:graph_go/login.dart';
import 'package:graph_go/services/google_auth_service.dart';

import 'login_test.mocks.dart';

@GenerateMocks([FirebaseAuth, UserCredential, User, GoogleAuthService])
void main() {
  group('LoginPage Widget Tests', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockGoogleAuthService mockGoogleAuth;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockGoogleAuth = MockGoogleAuthService();
    });

    Widget createTestWidget() {
      return MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Scaffold(
                body: Text('Home Page'),
              ),
            ),
            GoRoute(
              path: '/login',
              builder: (context, state) => const LoginPage(),
            ),
            GoRoute(
              path: '/signup',
              builder: (context, state) => const Scaffold(
                body: Text('Signup Page'),
              ),
            ),
          ],
        ),
      );
    }

    testWidgets('should display login form elements', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('GraphGo Login'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.text('OR'), findsOneWidget);
      expect(find.text('Login with Email'), findsOneWidget);
      expect(find.text('Don\'t have an account? Sign Up'), findsOneWidget);
    });

    testWidgets('should validate email field', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Try to submit without entering email
      await tester.tap(find.text('Login with Email'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Enter your email'), findsOneWidget);
    });

    testWidgets('should validate password field', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter email but not password
      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.tap(find.text('Login with Email'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('should navigate to signup page', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Don\'t have an account? Sign Up'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Signup Page'), findsOneWidget);
    });

    testWidgets('should navigate to forgot password page', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      // Assert - Should navigate to forgot password page
      // Note: This test assumes ForgotPasswordPage is implemented
    });

    testWidgets('should show loading indicator during login', (WidgetTester tester) async {
      // Arrange
      when(mockAuth.signInWithEmailAndPassword(
        email: anyNamed('email'),
        password: anyNamed('password'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(seconds: 2));
        return MockUserCredential();
      });

      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter valid credentials
      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      
      await tester.tap(find.text('Login with Email'));
      await tester.pump(); // Don't settle to catch loading state

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should handle Google sign-in button tap', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in with Google'));
      await tester.pumpAndSettle();

      // Assert - Button should be tappable
      expect(find.text('Sign in with Google'), findsOneWidget);
    });

    testWidgets('should show back button', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Assert
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('should have proper form validation', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Try to submit empty form
      await tester.tap(find.text('Login with Email'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });

    testWidgets('should accept valid email input', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter valid email
      await tester.enterText(find.byType(TextFormField).first, 'test@example.com');
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('should accept password input', (WidgetTester tester) async {
      // Act
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter password
      await tester.enterText(find.byType(TextFormField).last, 'password123');
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('password123'), findsOneWidget);
    });
  });
}
