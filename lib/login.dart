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

      // Update last sign-in time and role for driver profile
      if (user != null) {
        final profileService = ProfileService();
        // Check if driver profile exists, if not create it
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
          // Create driver profile if doesn't exist (might be existing user without profile)
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

      // Wait a bit for auth state to propagate
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify user is still logged in
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && mounted) {
        print('Redirecting to home page...');
        context.go('/');
        // Force router refresh to trigger redirect logic
        GoRouter.of(context).refresh();
        print('Redirect command sent');
      }
    } catch (e) {
      print('Email login failed: $e');
      if (mounted) {
        // Check if user is actually logged in despite the error (common with PigeonUserDetails error)
        await Future.delayed(const Duration(milliseconds: 200));
        final user = FirebaseAuth.instance.currentUser;
        
        // If user is logged in, don't show error - just redirect silently
        if (user != null) {
          print('User logged in despite error, redirecting silently...');
          context.go('/');
          GoRouter.of(context).refresh();
          return;
        }
        
        // Only show error if login actually failed
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

      // Wait for auth state to propagate
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Check if user is signed in (either through successful credential or error handling)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        if (mounted) {
          print('Google login successful: ${currentUser.email}');
          context.go('/');
          // Force router refresh to trigger redirect logic
          GoRouter.of(context).refresh();
        }
      } else if (userCredential == null) {
        // Handle the case where Google Sign-In had issues but user might still be signed in
        // Check again after a short delay
        await Future.delayed(const Duration(milliseconds: 500));
        final userAfterDelay = FirebaseAuth.instance.currentUser;
        if (userAfterDelay != null && mounted) {
          print('Google login successful (after delay): ${userAfterDelay.email}');
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
      
      // Always check if user is logged in before showing error
      await Future.delayed(const Duration(milliseconds: 300));
      final user = FirebaseAuth.instance.currentUser;
      
      // If user is logged in, redirect silently without showing error
      if (user != null && mounted) {
        print('User logged in despite error, redirecting silently...');
        context.go('/');
        GoRouter.of(context).refresh();
        return;
      }
      
      // Only show error if login actually failed
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
            fontFamily: 'Impact', // Ensure "Impact" is available in your fonts
            fontSize: 24, // Adjust size as needed
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
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (value) => value!.isEmpty ? "Enter your email" : null,
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (value) => value!.isEmpty ? "Enter your password" : null,
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor:isDarkMode ? kLightBackground : kDarkBackground, // Text color
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), // Padding
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), // Rounded corners
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ForgotPasswordPage()),
                  );
                },
                child: Text("Forgot Password?"),
              ),

              const SizedBox(height: 20),
              
              // Google Sign-In Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  icon: const Icon(
                    Icons.login,
                    size: 20,
                    color: Colors.blue,
                  ),
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
              
              // Divider
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
              
              // Email Login Button
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
                  foregroundColor: isDarkMode ? kLightBackground : kDarkBackground, // Text color
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15), // Padding
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10), // Rounded corners
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
