import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';

import 'models/delivery_address.dart';
import 'screens/home_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/addresses_screen.dart';
import 'screens/optimized_route_map_screen.dart';

import 'screens/driver_assigned_orders_screen.dart';
import 'providers/delivery_provider.dart';
import 'providers/graph_provider.dart';
import 'providers/route_provider.dart';

import 'login.dart';
import 'signup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    runApp(const GraphGoApp());
  } catch (e, stackTrace) {
    log('Error during app initialization: $e');
    log('Stack trace for the error: $stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Error initializing app. Check the logs for details: $e'),
          ),
        ),
      ),
    );
  }
}

class GraphGoApp extends StatelessWidget {
  const GraphGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeliveryProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => GraphProvider()),
        // Important: don't recreate RouteProvider on updates
        ChangeNotifierProvider(
          create: (ctx) => RouteProvider(
            graph: ctx.read<GraphProvider>(),
            deliveries: ctx.read<DeliveryProvider>(),
          ),
        ),
      ],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
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
  // ⬇️ Start on HOME, not /graph
  initialLocation: '/',
  redirect: (BuildContext context, GoRouterState state) {
    final user = FirebaseAuth.instance.currentUser;
    final isLoggedIn = user != null;
    final isLoggingIn =
        state.matchedLocation == '/login' || state.matchedLocation == '/signup';

    if (isLoggedIn && isLoggingIn) return '/';
    return null;
  },
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
      routes: <RouteBase>[
        GoRoute(
          path: 'graph',
          builder: (BuildContext context, GoRouterState state) => const GraphScreen(),
        ),
        GoRoute(
          path: 'addresses',
          builder: (BuildContext context, GoRouterState state) => const AddressesScreen(),
        ),
        GoRoute(
          path: 'settings',
          builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
        ),
        GoRoute(
          path: 'profile',
          builder: (BuildContext context, GoRouterState state) => const ProfileScreen(),
        ),
        // keep if anything links to /route-map; show GraphScreen
        GoRoute(
          path: 'route-map',
          builder: (BuildContext context, GoRouterState state) => const GraphScreen(),
        ),
        GoRoute(
          path: 'assigned-orders',
          builder: (BuildContext context, GoRouterState state) {
            return const DriverAssignedOrdersScreen();
          },
        ),
        GoRoute(
          path: 'optimized-route-map',
          builder: (BuildContext context, GoRouterState state) {
            final selectedOrders = state.extra as List<DeliveryAddress>? ?? [];
            return OptimizedRouteMapScreen(selectedOrders: selectedOrders);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/login',
      builder: (BuildContext context, GoRouterState state) => const LoginPage(),
    ),
    GoRoute(
      path: '/signup',
      builder: (BuildContext context, GoRouterState state) => const SignupPage(),
    ),
  ],
);
