import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  bool _isLoading = false;

  User? get user => _user;
  bool get isLoading => _isLoading;

  AuthProvider() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  Future<void> updateDisplayName(String name) async {
    if (_user != null) {
      _isLoading = true;
      notifyListeners();
      try {
        await _user!.updateDisplayName(name);
        _user = _auth.currentUser; // Refresh user data
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
