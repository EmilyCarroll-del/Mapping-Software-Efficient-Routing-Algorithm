// lib/screens/login.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';

// settings button on app bar needs this route to exist (you already have it)
import '../providers/settings_provider.dart'; // (kept because you had it imported)
// Google sign-in helper (your existing file)
import '../services/google_auth_service.dart';

// >>> NEW: profile + FCM updater <<<
import '../services/user_profile_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _isLoading = false;

  /// Let the user pick the UI they want to enter after login.
  /// (We still *persist* the chosen role if the user doc has none.)
  String _selectedRole = 'Admin';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _navigateBasedOnRole(String role) {
    if (!mounted) return;
    switch (role) {
      case 'Admin':
        Navigator.of(context).pushReplacementNamed('/admin-dashboard');
        break;
      case 'Driver':
      default:
        Navigator.of(context).pushReplacementNamed('/map');
        break;
    }
  }

  Future<void> _afterAuthSuccess({required String inferredRole}) async {
    // Merge profile + save FCM token (web+mobile) + write lastSignIn.
    await UserProfileService.updateOnSignIn(
      context,
      inferredRole: inferredRole, // only used if user doc has no role yet
    );

    // Navigate based on the current picker
    _navigateBasedOnRole(inferredRole);
  }

  Future<void> _loginEmailPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      await _afterAuthSuccess(inferredRole: _selectedRole);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Login failed: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final cred = await GoogleAuthService.signInWithGoogle();
      if (cred?.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Google Sign-In cancelled')),
          );
        }
        return;
      }

      await _afterAuthSuccess(inferredRole: _selectedRole);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Google Login failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter your email';
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!re.hasMatch(v.trim())) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Enter your password';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final iconColor = dark ? Colors.white : const Color(0xFF0D2B0D);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: () => Navigator.of(context).pushNamed('/settings'),
        ),
        title: const Text(
          'GraphGo',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_tree, size: 96, color: iconColor),
                const SizedBox(height: 20),
                Text(
                  'Welcome to GraphGo',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Log in as Admin or Driver to start',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),

                // ---- Google Sign-In ----
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _loginWithGoogle,
                    icon: SvgPicture.asset(
                      'assets/icons/google_icon.svg',
                      width: 20,
                      height: 20,
                    ),
                    label: const Text('Sign in with Google'),
                  ),
                ),

                const SizedBox(height: 18),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 18),

                // ---- Email / Password ----
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'Driver', child: Text('Driver')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedRole = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _email,
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        validator: _validatePassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pushNamed('/forgot'),
                          child: const Text('Forgot Password?'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _isLoading
                          ? const CircularProgressIndicator()
                          : SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loginEmailPassword,
                          style: ElevatedButton.styleFrom(
                            padding:
                            const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Login with Email'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/signup'),
                  child: const Text("Don't have an account? Sign Up"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
