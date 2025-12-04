
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';
import 'package:graph_go/providers/auth_provider.dart';
import 'package:graph_go/providers/delivery_provider.dart';
import 'package:graph_go/providers/settings_provider.dart';
import 'package:graph_go/providers/graph_provider.dart';
import 'package:graph_go/services/firestore_service.dart';
import 'package:graph_go/screens/login.dart';
import 'package:graph_go/screens/map_screen.dart';
import 'package:graph_go/screens/admin_dashboard_screen.dart';
import 'package:graph_go/screens/driver_assignments_screen.dart';
import 'package:graph_go/screens/settings_screen.dart';
import 'package:graph_go/screens/inbox.dart';
import 'package:graph_go/screens/profile_screen.dart';
import 'package:graph_go/screens/assigned_addresses_screen.dart';
import 'package:graph_go/screens/view_orders_screen.dart';
import 'package:graph_go/screens/add_order_screen.dart';
import 'package:graph_go/screens/admin_route_history_screen.dart';

class AuthStateNotifier extends ChangeNotifier {
  AuthStateNotifier() {
    FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
}

late final AuthStateNotifier authStateNotifier;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  authStateNotifier = AuthStateNotifier();
  final settingsProvider = await SettingsProvider.create();

  runApp(MyApp(settingsProvider: settingsProvider));
}

class MyApp extends StatelessWidget {
  final SettingsProvider settingsProvider;

  const MyApp({super.key, required this.settingsProvider});

  @override
  Widget build(BuildContext context) {
    const darkGreenColor = Color(0xFF0D2B0D);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GraphProvider()),
        Provider(create: (_) => FirestoreService()),
        ChangeNotifierProxyProvider<AuthProvider, DeliveryProvider>(
          create: (_) => DeliveryProvider(''),
          update: (_, auth, __) => DeliveryProvider((auth as AuthProvider).user?.uid ?? ''),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp.router(
            title: 'Graph & Go',
            theme: ThemeData(
              brightness: Brightness.light,
              primarySwatch: Colors.green,
              appBarTheme: const AppBarTheme(
                backgroundColor: darkGreenColor,
                foregroundColor: Colors.white,
              ),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              primarySwatch: Colors.green,
              appBarTheme: const AppBarTheme(
                backgroundColor: darkGreenColor,
                foregroundColor: Colors.white,
              ),
              scaffoldBackgroundColor: const Color(0xFF121212),
            ),
            themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            routerConfig: _router,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

// --- DEFINITIVE ROUTER FIX ---
late final GoRouter _router = GoRouter(
  refreshListenable: authStateNotifier, 
  redirect: (BuildContext context, GoRouterState state) {
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    final isLoggingIn = state.matchedLocation == '/login';

    // The only rule: if the user is not logged in and not on the login page,
    // redirect them to the login page.
    if (!isLoggedIn && !isLoggingIn) {
      return '/login';
    }

    // In all other cases, do not redirect. This allows the LoginPage to have
    // full control over navigation after a successful login.
    return null;
  },
  routes: <RouteBase>[
    // A default route is still needed for when the app first loads in a logged-in state.
    GoRoute(path: '/', builder: (_, __) => const AdminDashboardScreen()), 
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(path: '/map', builder: (_, __) => const MapScreen()),
    GoRoute(path: '/admin-dashboard', builder: (_, __) => const AdminDashboardScreen()),
    GoRoute(path: '/driver-assignments', builder: (_, __) => const DriverAssignmentsScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/inbox', builder: (_, __) => const InboxPage()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/assigned-addresses', builder: (_, __) => const AssignedAddressesScreen()),
    GoRoute(path: '/view-orders', builder: (_, __) => const ViewOrdersScreen()),
    GoRoute(path: '/add-order', builder: (_, __) => const AddOrderScreen()),
    GoRoute(path: '/admin-route-history', builder: (_, __) => const AdminRouteHistoryScreen()),
  ],
);
