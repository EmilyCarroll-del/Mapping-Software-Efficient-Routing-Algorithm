import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/driver_assigned_orders_screen.dart';
import 'screens/inbox.dart';
import 'screens/notifications_screen.dart';
import 'providers/delivery_provider.dart';
import 'services/notification_service.dart';
import 'widgets/bottom_navigation_bar.dart';
import 'screens/route_history_screen.dart';
import 'screens/chat_page.dart';
import 'login.dart';
import 'signup.dart';

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling background message: ${message.messageId}');
  
  // Create notification directly in Firestore
  final db = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final currentUser = auth.currentUser;
  
  if (currentUser != null) {
    await db.collection('notifications').add({
      'userId': currentUser.uid,
      'type': message.data['type'] ?? 'system',
      'title': message.notification?.title ?? message.data['title'] ?? 'Notification',
      'message': message.notification?.body ?? message.data['message'] ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      'actionType': message.data['actionType'] ?? 'none',
      'actionData': {
        'orderId': message.data['orderId'],
        'conversationId': message.data['conversationId'],
        'url': message.data['url'],
      },
      'metadata': {},
    });
  }
}

// Listenable class for auth state changes
class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      notifyListeners();
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  
  // Initialize notification service when user is logged in
  // Use a singleton instance to avoid multiple initializations
  final notificationService = NotificationService();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
      notificationService.initialize();
    } else {
      notificationService.dispose();
    }
  });
  
  // Also initialize if user is already logged in
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null) {
    notificationService.initialize();
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
  refreshListenable: _AuthStateNotifier(),
  redirect: (BuildContext context, GoRouterState state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    final isLoggingIn = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
    
    // If user is logged in and trying to access login/signup pages, redirect to home
    if (isLoggedIn && isLoggingIn) {
      return '/';
    }
    
    // Note: Mobile app is exclusively for drivers. Admin functionality is web-only.
    // All mobile app signups automatically set userType: 'driver'
    // All admin users MUST have a companyCode (required during web app signup)
    
    // No automatic redirect to login - let the home screen handle it
    return null; // No redirect needed
  },
  routes: <RouteBase>[
    ShellRoute(
      builder: (context, state, child) {
        return Scaffold(
          body: child,
          bottomNavigationBar: CustomBottomNavigationBar(currentLocation: state.matchedLocation),
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
                ? (state.extra as Map<String, dynamic>)['openConversationId']?.toString()
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
          builder: (BuildContext context, GoRouterState state) {
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
            final otherUserName = (extras['otherUserName']?.toString()) ?? 'User';
            final orderId = extras['orderId']?.toString();
            final orderTitle = extras['orderTitle']?.toString();
            final isOldFormat = (extras['isOldFormat'] is bool) ? extras['isOldFormat'] as bool : false;

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