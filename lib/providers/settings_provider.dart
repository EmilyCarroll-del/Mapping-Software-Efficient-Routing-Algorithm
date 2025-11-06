import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const String _darkModeKey = 'darkMode';
  static const String _isLoggedInKey = 'isLoggedIn';

  // For local development, point to your Flask server.
  // For production, this would be your deployed server's URL.
  static const String _apiBaseUrl = "http://localhost:5000";

  bool _darkMode = false;
  bool _isLoggedIn = false;

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  bool get darkMode => _darkMode;
  bool get isLoggedIn => _isLoggedIn;

  SettingsProvider._();

  static Future<SettingsProvider> create() async {
    final provider = SettingsProvider._();
    await provider._loadPreferences();
    if (kIsWeb) {
      await provider.setupFCM();
    }
    return provider;
  }

  Future<void> setupFCM() async {
    final messaging = FirebaseMessaging.instance;
    // Use the VAPID key here for web push authentication
    const vapidKey = "BAEXeAwTaHrsEDu5-we5yu9YAnnOaEvKqF8s_dM_J2WJbp-9T2YoL54DRa2T61LBSjbHgBSNU3Xh2KmPvoS1ILs";

    final settings = await messaging.requestPermission();

    if (kDebugMode) {
      print("FCM Settings: ${settings.authorizationStatus}");
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
          content: Text("${notification.title}\n${notification.body}"),
          duration: const Duration(seconds: 5),
        ));
      }
    });

    messaging.onTokenRefresh.listen((token) {
      if (kDebugMode) {
        print("FCM token refreshed: $token");
      }
      registerAdminToken(token);
    });

    // Get the token and register it
    final token = await messaging.getToken(vapidKey: vapidKey);
    if (token != null) {
      if (kDebugMode) {
        print("FCM token: $token");
      }
      registerAdminToken(token);
    } else {
       if (kDebugMode) {
        print("FCM token retrieval failed. Check browser permissions.");
      }
    }
  }

  Future<void> registerAdminToken(String token) async {
    try {
      final response = await http.post(
        Uri.parse("$_apiBaseUrl/api/notifications/register"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'role': 'admin'}),
      );
      if (kDebugMode) {
        print(
            "Token registration response: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Error registering token: $e");
      }
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _darkMode = prefs.getBool(_darkModeKey) ?? false;
    _isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    notifyListeners();
  }

  Future<void> _saveDarkModePreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, _darkMode);
  }

  Future<void> _saveLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, _isLoggedIn);
  }

  void toggleDarkMode() {
    _darkMode = !_darkMode;
    _saveDarkModePreference();
    notifyListeners();
  }

  void login() {
    _isLoggedIn = true;
    _saveLoginStatus();
    notifyListeners();
  }

  void logout() {
    _isLoggedIn = false;
    _saveLoginStatus();
    notifyListeners();
  }
}
