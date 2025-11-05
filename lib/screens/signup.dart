// lib/screens/signup.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// include the same profile setup as login
import '../services/user_profile_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isLoading = false;

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return "Email is required.";
    final emailRegex =
    RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(value)) return "Enter a valid email.";
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return "Password is required.";
    if (value.length < 12) return "Password must be at least 12 characters.";
    if (!RegExp(r'[A-Z]').hasMatch(value)) return "Must contain 1 uppercase.";
    if (!RegExp(r'\d').hasMatch(value)) return "Must contain 1 number.";
    if (!RegExp(r'[!@#\$%^&*(),.?\":{}|<>]').hasMatch(value)) {
      return "Must contain 1 special character.";
    }
    return null;
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      final user = cred.user;
      if (user == null) throw Exception("User creation failed");

      // initialize Firestore profile
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': _email.text.trim(),
        'provider': 'email',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // ensure profile shape + token
      await UserProfileService.updateOnSignIn(context, inferredRole: 'Driver');

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/map');
    } on FirebaseAuthException catch (e) {
      final msg = e.code == 'email-already-in-use'
          ? "This email is already registered."
          : e.message ?? "Signup failed.";
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _email,
                    validator: _validateEmail,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    validator: _validatePassword,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 28),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _signUp,
                      style: ElevatedButton.styleFrom(
                        padding:
                        const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Create Account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
