import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  static const String _darkModeKey = 'darkMode';
  static const String _isLoggedInKey = 'isLoggedIn';

  bool _darkMode = false;
  bool _isLoggedIn = false;

  bool get darkMode => _darkMode;
  bool get isLoggedIn => _isLoggedIn;

  // Private constructor for async initialization
  SettingsProvider._();

  // Static async method to create an instance
  static Future<SettingsProvider> create() async {
    final provider = SettingsProvider._();
    await provider._loadPreferences();
    return provider;
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
