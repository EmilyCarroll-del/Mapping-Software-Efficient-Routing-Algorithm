import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'services/google_auth_service.dart';
import 'forgot_password.dart';
import 'colors.dart';

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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Update last sign-in time
      await GoogleAuthService.updateLastSignIn();

      // Navigate to home and refresh the state
      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Failed: ${e.toString()}")),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final UserCredential? userCredential = await GoogleAuthService.signInWithGoogle();
      
      // Check if user is signed in (either through successful credential or error handling)
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (mounted) {
          context.go('/');
        }
      } else if (userCredential == null) {
        // Handle the case where Google Sign-In had issues but user might still be signed in
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Google Sign-In had issues, but you might still be signed in")),
        );
        // Check again after a short delay
        await Future.delayed(const Duration(seconds: 1));
        final userAfterDelay = FirebaseAuth.instance.currentUser;
        if (userAfterDelay != null && mounted) {
          context.go('/');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Google Login Failed: ${e.toString()}")),
      );
    } finally {
      setState(() => _isLoading = false);
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
