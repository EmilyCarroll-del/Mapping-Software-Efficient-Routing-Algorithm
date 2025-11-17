import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'login.dart';
import 'providers/delivery_provider.dart';
import 'screens/chat_page.dart';
import 'screens/driver_assigned_orders_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inbox.dart';
import 'screens/notifications_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/route_history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/notification_service.dart';
import 'signup.dart';
import 'widgets/bottom_navigation_bar.dart';

// ---------------------------------------------------------------------------
// Global navigator key so NotificationService can trigger navigation
// when a notification is tapped.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

// ---------------------------------------------------------------------------
// Background FCM handler (must be a top-level function).
// We **do not** write Firestore notifications here to avoid duplicates.
// Use it only for logging or preloading if you need to.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // print('BG message: ${message.messageId} data=${message.data}');
}
// ---------------------------------------------------------------------------

// Listenable class for auth state changes (used by GoRouter)
class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      notifyListeners();
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    print('Loading .env file...');
    await dotenv.load(fileName: ".env");

    // Verify that .env file was loaded successfully
    final hasApiKey =
        dotenv.env['AWS_API_KEY'] != null && dotenv.env['AWS_API_KEY']!.isNotEmpty;
    final hasRegion = dotenv.env['AWS_REGION'] != null;
    final hasCalculator = dotenv.env['AWS_CALCULATOR_NAME'] != null;

    print('✅ .env file loaded successfully');
    print('AWS_API_KEY: ${hasApiKey ? "Found" : "Not found"}');
    print('AWS_REGION: ${hasRegion ? dotenv.env['AWS_REGION'] : "Not found"}');
    print('AWS_CALCULATOR_NAME: ${hasCalculator ? dotenv.env['AWS_CALCULATOR_NAME'] : "Not found"}');

    if (!hasApiKey && !hasRegion) {
      print('⚠️ Warning: AWS credentials not found in .env file');
      print('   AWS Route Service will not be available');
      print('   To enable AWS routing:');
      print('   1. Ensure .env file exists in project root');
      print('   2. Add AWS_API_KEY=your_key to .env');
      print('   3. Add AWS_REGION=us-east-1 to .env');
      print('   4. Add AWS_CALCULATOR_NAME=GraphGoRouteCalculator to .env');
      print('   5. Ensure .env is listed in pubspec.yaml assets section');
    }
  } catch (e, stackTrace) {
    print('❌ Error loading .env file: $e');
    print('Stack trace: $stackTrace');
    print('AWS Route Service will not be available');
    print('');
    print('Troubleshooting steps:');
    print('1. Ensure .env file exists in the project root directory');
    print('2. Ensure .env is listed in pubspec.yaml under flutter: assets:');
    print('3. Run "flutter pub get" to refresh assets');
    print('4. Restart the app after adding .env to assets');
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the background handler (no Firestore writes here)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize NotificationService tied to auth state
  final notificationService = NotificationService(_rootNavigatorKey);

  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      // Set the user's role to 'Driver' on every login
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'role': 'Driver'}, SetOptions(merge: true));

      notificationService.initialize();
    } else {
      notificationService.dispose();
    }
  });

  // If already logged in at startup
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    await notificationService.initialize();
  }

  runApp(const GraphGoApp());
}

class GraphGoApp extends StatelessWidget {
  const GraphGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => DeliveryProvider()..initialize(),
      child: MaterialApp.router(
        title: 'GraphGo - Route Optimization',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        routerConfig: _router,
      ),
    );
  }
}

final GoRouter _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  refreshListenable: _AuthStateNotifier(),
  redirect: (BuildContext context, GoRouterState state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    final isLoggingIn =
        state.matchedLocation == '/login' || state.matchedLocation == '/signup';

    // If user is logged in and trying to access login/signup pages, redirect to home
    if (isLoggedIn && isLoggingIn) {
      return '/';
    }

    // COMPANY CODE SYSTEM - USER TYPE RULES:
    //
    // Mobile app is exclusively for drivers. Admin functionality is web-only.
    //
    // DRIVERS (Mobile App):
    //   - All mobile app signups automatically set userType: 'driver'
    //   - Company code is OPTIONAL for drivers
    //     * With companyCode: Linked to company (can only work with matching admins)
    //     * Without companyCode: Freelancer (can work with any admin)
    //     * Company code can be added/updated in profile screen
    //
    // ADMINS (Web App Only):
    //   - All admin users MUST have a companyCode (required during web app signup)
    //   - Company Admins: Share companyCode (e.g., FedEx, DHL, UPS, Amazon)
    //   - Individual Admins: Have unique companyCode (freelancers looking for drivers)

    // No automatic redirect to login - let the home screen handle it
    return null; // No redirect needed
  },
  routes: <RouteBase>[
    ShellRoute(
      builder: (context, state, child) {
        return Scaffold(
          body: child,
          bottomNavigationBar:
          CustomBottomNavigationBar(currentLocation: state.matchedLocation),
        );
      },
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) {
            return const HomeScreen();
          },
        ),
        GoRoute(
          path: '/inbox',
          builder: (BuildContext context, GoRouterState state) {
            final openId = state.extra is Map<String, dynamic>
                ? (state.extra as Map<String, dynamic>)['openConversationId']
                ?.toString()
                : null;
            return InboxPage(openConversationId: openId);
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (BuildContext context, GoRouterState state) {
            return const ProfileScreen();
          },
        ),
        GoRoute(
          path: '/notifications',
          builder: (BuildContext context, GoRouterState) {
            return const NotificationsScreen();
          },
        ),
        GoRoute(
          path: '/route-history',
          builder: (BuildContext context, GoRouterState state) {
            return const RouteHistoryScreen();
          },
        ),
        GoRoute(
          path: '/assigned-orders',
          builder: (BuildContext context, GoRouterState state) {
            return const DriverAssignedOrdersScreen();
          },
        ),
        GoRoute(
          path: '/chat',
          builder: (BuildContext context, GoRouterState state) {
            final extras = state.extra is Map<String, dynamic>
                ? state.extra as Map<String, dynamic>
                : <String, dynamic>{};

            final conversationId = extras['conversationId']?.toString();
            final otherUserId = extras['otherUserId']?.toString();
            final otherUserName =
                (extras['otherUserName']?.toString()) ?? 'User';
            final orderId = extras['orderId']?.toString();
            final orderTitle = extras['orderTitle']?.toString();
            final isOldFormat = (extras['isOldFormat'] is bool)
                ? extras['isOldFormat'] as bool
                : false;

            if (conversationId == null || otherUserId == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Chat')),
                body: const Center(
                  child: Text('Invalid chat parameters'),
                ),
              );
            }

            return ChatPage(
              conversationId: conversationId,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
              orderId: orderId,
              orderTitle: orderTitle,
              isOldFormat: isOldFormat,
            );
          },
        ),
        GoRoute(
          path: '/graph',
          builder: (BuildContext context, GoRouterState state) {
            return const GraphScreen();
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (BuildContext context, GoRouterState state) {
            return const SettingsScreen();
          },
        ),
      ],
    ),
    GoRoute(
      path: '/login',
      builder: (BuildContext context, GoRouterState state) {
        return const LoginPage();
      },
    ),
    GoRoute(
      path: '/signup',
      builder: (BuildContext context, GoRouterState state) {
        return const SignupPage();
      },
    ),
  ],
);
