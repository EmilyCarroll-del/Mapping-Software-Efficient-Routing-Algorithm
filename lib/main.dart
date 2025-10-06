import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
                background: Colors.black,
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
              "/adminDashboard": (context) => const AdminDashboardScreen(),
            },
          );
        },
      ),
    );
  }
}
