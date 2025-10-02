import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../services/google_auth_service.dart';
import '../colors.dart';

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
  bool _rememberMe = false;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (_rememberMe) {
        settingsProvider.login();
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/map');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Failed: ${e.toString()}")),
      );
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    try {
      final UserCredential? userCredential = await GoogleAuthService.signInWithGoogle();

      if (FirebaseAuth.instance.currentUser != null) {
        settingsProvider.login();
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/map');
        }
      } else if (userCredential == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Google Sign-In was cancelled or failed.")),
        );
      }
    } catch (e) {
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Google Login Failed: ${e.toString()}")),
          );
       }
    } finally {
      if(mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GraphGo Login'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Back to Home',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
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
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (val) {
                        setState(() => _rememberMe = val ?? false);
                      },
                    ),
                    const Text("Remember Me"),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed('/forgot');
                },
                child: const Text("Forgot Password?"),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _loginWithGoogle,
                  icon: const Icon(Icons.login, size: 20, color: Colors.blue),
                  label: const Text('Sign in with Google'),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('OR'),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _login,
                  child: const Text('Login with Email'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/signup'),
                child: const Text("Don't have an account? Sign Up"),
              ),

              // The debug override button has been removed.
            ],
          ),
        ),
      ),
    );
  }
}
