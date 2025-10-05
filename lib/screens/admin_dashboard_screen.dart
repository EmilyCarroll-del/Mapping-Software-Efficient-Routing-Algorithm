import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/delivery_address.dart';
import '../services/google_auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/address_list.dart';
import '../widgets/add_edit_address_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  User? _user;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted) {
        setState(() {
          _user = user;
        });
      }
    });
  }

  void _showAddEditAddressDialog({DeliveryAddress? address}) {
    if (_user == null) return;
    showDialog(
      context: context,
      builder: (context) => AddEditAddressDialog(
        address: address,
        userId: _user!.uid,
        onSave: (address) {
          _firestoreService.saveAddress(address);
        },
      ),
    );
  }

  Future<void> _showUploadCsvDialog() async {
    if (_user == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || !mounted) return;

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) return;

      final content = utf8.decode(bytes);
      final list = const CsvToListConverter().convert(content);

      if (list.isNotEmpty) {
        list.removeAt(0); // remove header
      }

      final addresses = list.map((row) {
        try {
          return DeliveryAddress(
            userId: _user!.uid,
            streetAddress: row[0].toString(),
            city: row[1].toString(),
            state: row[2].toString(),
            zipCode: row[3].toString(),
            notes: row.length > 4 ? row[4].toString() : null,
          );
        } catch (e) {
          print('Error parsing row: $row, error: $e');
          return null;
        }
      }).where((address) => address != null).cast<DeliveryAddress>().toList();

      if (!mounted) return; // Check if the widget is still in the tree

      if (addresses.isNotEmpty) {
        try {
          await _firestoreService.saveAddressesFromCsv(addresses);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Addresses uploaded successfully!')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error uploading addresses: $e')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No valid addresses found in the CSV file.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  void _deleteAddress(String addressId) {
    _firestoreService.deleteAddress(addressId);
  }

  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Login Failed: ${e.message}")),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await GoogleAuthService.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Google Login Failed: ${e.toString()}")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: () => Navigator.of(context).pushNamed('/settings'),
        ),
        title: const Text('GraphGo Admin', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        actions: [
          if (_user != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(child: Text(_user!.email ?? '', style: const TextStyle(color: Colors.white))),
            ),
          if (_user != null)
            TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.white, size: 18),
              label: const Text('Logout', style: TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16.0)),
            ),
        ],
      ),
      body: _user == null ? _buildLoginForm(context) : _buildLoggedInView(context),
    );
  }

  Widget _buildLoggedInView(BuildContext context) {
    if (_user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _showAddEditAddressDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add Address'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _showUploadCsvDialog,
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload CSV'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'List of Addresses',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Expanded(
            child: AddressList(
              onEdit: (address) => _showAddEditAddressDialog(address: address),
              onDelete: _deleteAddress,
              addressesStream: _firestoreService.getAddresses(_user!.uid),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white
              ),
              child: const Text('Release to Drivers'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final ThemeData currentTheme = Theme.of(context);
    final bool darkMode = currentTheme.brightness == Brightness.dark;
    final Color welcomeTextColor = darkMode ? Colors.white : Colors.black87;
    final Color sloganTextColor = darkMode ? Colors.grey[300]! : Colors.black54;
    final Color iconColor = darkMode ? Colors.white : const Color(0xFF0D2B0D);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.account_tree,
              size: 100,
              color: iconColor,
            ),
            const SizedBox(height: 20),
            Text(
              'Welcome to GraphGo',
              style: currentTheme.textTheme.headlineMedium?.copyWith(
                    fontSize: (currentTheme.textTheme.headlineMedium?.fontSize ?? 28) * 1.15,
                    fontWeight: FontWeight.bold,
                    color: welcomeTextColor,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Admin Panel Access',
              style: currentTheme.textTheme.bodyLarge?.copyWith(
                    fontSize: (currentTheme.textTheme.bodyLarge?.fontSize ?? 16) * 1.1,
                    color: sloganTextColor,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _loginWithGoogle,
                      icon: SvgPicture.asset('assets/icons/google_icon.svg', width: 20, height: 20),
                      label: const Text('Sign in with Google'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR'),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) => value!.isEmpty ? "Enter your email" : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                          obscureText: true,
                          validator: (value) => value!.isEmpty ? "Enter your password" : null,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(context).pushNamed('/forgot');
                            },
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _isLoading
                            ? const CircularProgressIndicator()
                            : SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _loginWithEmail,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Login with Email'),
                                ),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/signup');
                    },
                    child: const Text("Don't have an account? Sign Up"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
