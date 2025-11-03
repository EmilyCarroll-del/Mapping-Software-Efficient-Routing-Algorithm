import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:js/js.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';

// Providers
import 'providers/graph_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/delivery_provider.dart';
import 'providers/auth_provider.dart';

// Screens
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/login.dart';
import 'screens/signup.dart';
import 'screens/forgot_password.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/assigned_addresses_screen.dart';
import 'screens/driver_assignments_screen.dart';

@JS('showBrowserNotification')
external void _showBrowserNotification(String title, String body, String url);


const String googleApiKey = "AIzaSyCFx_8PW_R6rGq-julkwV4JJGixbzmnP74";

/// Handles background messages (not used by web, but keep it for mobile support)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // You can log or store messages here if needed
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Set up FCM background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 🔹 Web: ask for permission to show notifications
  if (kIsWeb) {
    await FirebaseMessaging.instance.requestPermission();
  }

  // 🔹 Web: request FCM token (VAPID key needed for browser push)
  if (kIsWeb) {
    const vapidKey = "BAEXeAwTaHrsEDu5-we5yu9YAnnOaEvKqF8s_dM_J2WJbp-9T2YoL54DRa2T61LBSjbHgBSNU3Xh2KmPvoS1ILs"; // VAPID key here
    final token = await FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
    if (token != null) {
      debugPrint("FCM Token (Web): $token");
      // Optionally: send this token to your Flask backend
      // await http.post(Uri.parse('https://your-server.com/api/notifications/register'),
      //   body: jsonEncode({'token': token, 'role': 'admin'}));
    } else {
      debugPrint("No FCM token retrieved (permission denied or blocked)");
    }

    // Listen for foreground messages (tab active)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title = message.notification?.title ?? message.data['title'] ?? 'Update';
      final body  = message.notification?.body  ?? message.data['body']  ?? '';

      // Optional deep-link/route to open when clicked
      final url   = message.data['url'] ?? '/admin-dashboard';

      // Show a real browser notification (foreground)
      if (kIsWeb) {
        try {
          _showBrowserNotification(title, body, url);
        } catch (_) {
          // As a fallback, still log or show a SnackBar in your UI
          debugPrint('📩 Foreground message: $title - $body');
        }
      } else {
        // (Mobile path): you might use flutter_local_notifications, etc.
        debugPrint('📩 Mobile foreground: $title - $body');
      }
    });

  }

  final settingsProvider = await SettingsProvider.create();
  runApp(MyApp(settingsProvider: settingsProvider));
}

class MyApp extends StatelessWidget {
  final SettingsProvider settingsProvider;

  const MyApp({super.key, required this.settingsProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GraphProvider()),
        ChangeNotifierProvider(create: (_) => DeliveryProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: settingsProvider),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: "GraphGo",
            themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            theme: ThemeData(
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light),
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF0D2B0D),
                foregroundColor: Colors.white,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.dark(
                primary: Colors.deepPurple.shade300,
                surface: Colors.grey.shade800,
              ),
              scaffoldBackgroundColor: Colors.black,
              appBarTheme: const AppBarTheme(
                backgroundColor: Color(0xFF0D2B0D),
                foregroundColor: Colors.white,
              ),
              cardTheme: CardThemeData(
                color: Colors.grey[850],
                elevation: 2,
              ),
              useMaterial3: true,
            ),
            home: kIsWeb ? const LoginPage() : const HomeScreen(),
            routes: {
              "/login": (context) => const LoginPage(),
              "/signup": (context) => const SignupPage(),
              "/forgot": (context) => const ForgotPasswordPage(),
              "/map": (context) => const MapScreen(),
              "/settings": (context) => const SettingsScreen(),
              "/profile": (context) => const ProfileScreen(),
              "/admin-dashboard": (context) => const AdminDashboardScreen(),
              "/assigned-addresses": (context) => AssignedAddressesScreen(),
              "/driver-assignments": (context) => const DriverAssignmentsScreen(),
            },
          );
        },
      ),
    );
  }
}
