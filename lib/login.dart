import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'services/google_auth_service.dart';
import 'services/profile_service.dart';
import 'forgot_password.dart';
import 'colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      print('Starting email login...');
      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final user = userCredential.user;
      print('Email login successful: ${user?.email}');

      if (user != null) {
        final profileService = ProfileService();
        final profileExists = await profileService.profileExists(user.uid, 'driver');

        if (profileExists) {
          await profileService.updateProfile(
            user.uid,
            'driver',
            {
              'last_sign_in': FieldValue.serverTimestamp(),
              'role': 'Driver',
            },
          );
        } else {
          await profileService.createProfile(
            user.uid,
            'driver',
            {
              'email': user.email ?? '',
              'provider': 'email',
              'userType': 'driver',
              'role': 'Driver',
              'last_sign_in': FieldValue.serverTimestamp(),
            },
          );
        }
      }

      await Future.delayed(const Duration(milliseconds: 100));

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && mounted) {
        context.go('/');
        GoRouter.of(context).refresh();
      }
    } catch (e) {
      print('Email login failed: $e');

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 200));
        final user = FirebaseAuth.instance.currentUser;

        if (user != null) {
          context.go('/');
          GoRouter.of(context).refresh();
          return;
        }

        String errorMessage = "Login Failed: ${e.toString()}";
        if (e.toString().contains('PigeonUserDetails') ||
            e.toString().contains('type \'List<Object?>\' is not a subtype')) {
          errorMessage = "Login Failed: Authentication error. Please try again.";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final UserCredential? userCredential = await GoogleAuthService.signInWithGoogle();
      final user = userCredential?.user;

      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'last_sign_in': FieldValue.serverTimestamp(),
          'role': 'Driver',
        }, SetOptions(merge: true));
      }

      await Future.delayed(const Duration(milliseconds: 200));

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        if (mounted) {
          context.go('/');
          GoRouter.of(context).refresh();
        }
      } else if (userCredential == null) {
        await Future.delayed(const Duration(milliseconds: 500));
        final userAfterDelay = FirebaseAuth.instance.currentUser;
        if (userAfterDelay != null && mounted) {
          context.go('/');
          GoRouter.of(context).refresh();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Google Sign-In failed. Please try again.")),
            );
          }
        }
      }
    } catch (e) {
      print('Google login error: $e');

      await Future.delayed(const Duration(milliseconds: 300));
      final user = FirebaseAuth.instance.currentUser;

      if (user != null && mounted) {
        context.go('/');
        GoRouter.of(context).refresh();
        return;
      }

      String errorMessage = "Google Login Failed: ${e.toString()}";
      if (e.toString().contains('PigeonUserDetails') ||
          e.toString().contains('type \'List<Object?>\' is not a subtype')) {
        errorMessage = "Google Sign-In failed. Please try again.";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GraphGo Login',
          style: TextStyle(
            fontFamily: 'Impact',
            fontSize: 24,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
          tooltip: 'Back to Home',
        ),
        iconTheme: IconThemeData(
          color: isDarkMode ? kDarkBackground : kLightBackground,
        ),
        foregroundColor: isDarkMode ? kDarkBackground : kLightBackground,
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),

        child: Form(
          key: _formKey,

          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              // EMAIL FIELD (Enter = nothing, Tab = OK)
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value!.isEmpty ? "Enter your email" : null,
              ),

              // PASSWORD FIELD (Enter = LOGIN)
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _login(),  // ENTER logs in
                validator: (value) => value!.isEmpty ? "Enter your password" : null,
              ),

              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: isDarkMode ? kLightBackground : kDarkBackground,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ForgotPasswordPage()),
                  );
                },
                child: const Text("Forgot Password?"),
              ),

              const SizedBox(height: 20),

              // GOOGLE SIGN-IN BUTTON
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  icon: const Icon(Icons.login, size: 20, color: Colors.blue),
                  label: const Text('Sign in with Google'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: isDarkMode ? kDarkText : kLightText,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 16),

              // EMAIL LOGIN BUTTON
              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _login,
                  child: const Text('Login with Email'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? kLightBackground : kDarkBackground,
                    foregroundColor: isDarkMode ? kDarkBackground : kLightBackground,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: isDarkMode ? kLightBackground : kDarkBackground,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => context.go('/signup'),
                child: const Text("Don't have an account? Sign Up"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
