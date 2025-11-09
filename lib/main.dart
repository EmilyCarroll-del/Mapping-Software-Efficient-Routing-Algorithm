// lib/main.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register the background handler (no Firestore writes here)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize NotificationService tied to auth state
  final notificationService = NotificationService();
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null) {
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
      create: (_) => DeliveryProvider()..initialize(),
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
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    final isAuthRoute =
        state.matchedLocation == '/login' || state.matchedLocation == '/signup';

    if (isLoggedIn && isAuthRoute) return '/';
    return null;
  },
  routes: <RouteBase>[
    ShellRoute(
      builder: (context, state, child) => Scaffold(
        body: child,
        bottomNavigationBar:
        CustomBottomNavigationBar(currentLocation: state.matchedLocation),
      ),
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/inbox',
          builder: (_, state) {
            final extra = state.extra;
            final openId = extra is Map<String, dynamic>
                ? extra['openConversationId']?.toString()
                : null;
            return InboxPage(openConversationId: openId);
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (_, __) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        GoRoute(
          path: '/route-history',
          builder: (_, __) => const RouteHistoryScreen(),
        ),
        GoRoute(
          path: '/assigned-orders',
          builder: (_, __) => const DriverAssignedOrdersScreen(),
        ),
        GoRoute(
          path: '/chat',
          builder: (_, state) {
            final extras =
            state.extra is Map<String, dynamic> ? state.extra as Map<String, dynamic> : {};
            final conversationId = extras['conversationId']?.toString();
            final otherUserId = extras['otherUserId']?.toString();
            final otherUserName = (extras['otherUserName']?.toString()) ?? 'User';
            final orderId = extras['orderId']?.toString();
            final orderTitle = extras['orderTitle']?.toString();
            final isOldFormat =
            extras['isOldFormat'] is bool ? extras['isOldFormat'] as bool : false;

            if (conversationId == null || otherUserId == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Chat')),
                body: const Center(child: Text('Invalid chat parameters')),
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
          builder: (_, __) => const GraphScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginPage(),
    ),
    GoRoute(
      path: '/signup',
      builder: (_, __) => const SignupPage(),
    ),
  ],
);
