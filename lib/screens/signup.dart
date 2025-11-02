import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/company_service.dart';
import '../models/company_model.dart';
import '../services/profile_service.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _companyCodeController = TextEditingController();
  bool _isLoading = false;

  final CompanyService _companyService = CompanyService();
  final ProfileService _profileService = ProfileService();
  List<Company> _companies = [];
  String? _selectedCompanyId; // Store company ID when selected
  String? _selectedCompanyCode; // Store generated/entered code
  bool _loadingCompanies = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _companyCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanies() async {
    setState(() => _loadingCompanies = true);
    try {
      _companies = await _companyService.getAllCompanies();
      setState(() => _loadingCompanies = false);
    } catch (e) {
      print('Error loading companies: $e');
      setState(() => _loadingCompanies = false);
    }
  }

  Future<void> _showManualCodeEntryDialog() async {
    final TextEditingController codeController = TextEditingController();
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Enter Company Code'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter a company code (alphanumeric, 1-20 characters):',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: codeController,
                  maxLength: 20,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Company Code',
                    hintText: 'ABC123',
                    border: OutlineInputBorder(),
                    counterText: '',
                    helperText: 'Optional for freelancer admins',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return null; // Optional
                    }
                    final trimmed = value.trim();
                    if (trimmed.length > 20) {
                      return 'Code must be 20 characters or less';
                    }
                    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(trimmed)) {
                      return 'Code must contain only letters and numbers';
                    }
                    return null;
                  },
                  autofocus: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final code = codeController.text.trim();
                  Navigator.of(dialogContext).pop(code.isEmpty ? null : code);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          _selectedCompanyCode = result;
          _companyCodeController.text = result;
        });
      }
    });
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return "Email is required.";
    }
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}\$');
    if (!emailRegex.hasMatch(value)) {
      return "Please enter a valid email address.";
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return "Password is required.";
    if (value.length < 12) return "Password must be at least 12 characters.";
    if (!RegExp(r'[A-Z]').hasMatch(value)) return "Must contain 1 uppercase letter.";
    if (!RegExp(r'\\d').hasMatch(value)) return "Must contain 1 number.";
    if (!RegExp(r'[!@#\\\$%^&*(),.?":{}|<>]').hasMatch(value)) return "Must contain 1 special character.";
    return null;
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Create admin user profile in separate document: users/{uid}_admin
      // This allows same email to have separate admin and driver profiles
      // - With companyCode: Admin is linked to company
      // - Without companyCode: Admin is freelancer (handles own dispatches)
      await _profileService.createProfile(
        userCredential.user!.uid,
        'admin',
        {
          'email': _emailController.text.trim(),
          'provider': 'email',
          'userType': 'admin', // Web app users are always admins
          'companyCode': _selectedCompanyCode ?? '', // Optional for admin users
          'role': 'Admin',
        },
      );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/map');
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      if (e.code == 'email-already-in-use') {
        errorMessage = "This email is already registered. Please log in or use a different email.";
      } else {
        errorMessage = "Signup Failed: \${e.message}";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("An unexpected error occurred: \${e.toString()}")),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
          tooltip: 'Back to Login',
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Username (Email)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: Tooltip(
                        message: 'Password must be at least 12 characters long and include:\\n'
                            '- 1 uppercase letter\\n'
                            '- 1 number\\n'
                            '- 1 special character (!@#\\\$%^&*(),.?":{}|<>)',
                        child: const Icon(Icons.help_outline),
                      ),
                    ),
                    obscureText: true,
                    validator: _validatePassword,
                  ),
                  const SizedBox(height: 16),
                  // Company Code (OPTIONAL for admin users)
                  _loadingCompanies
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String?>(
                                    value: _selectedCompanyId,
                                    decoration: const InputDecoration(
                                      labelText: 'Company Code (Optional)',
                                      border: OutlineInputBorder(),
                                      helperText: 'Leave empty for freelancer admin',
                                    ),
                                    hint: const Text('Select company (optional)'),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('None (Freelancer Admin)'),
                                      ),
                                      ..._companies.map((company) {
                                        String displayText = company.name;
                                        if (company.codeRangeStart != null && company.codeRangeEnd != null) {
                                          displayText = '${company.name} (${company.codeRangeStart}-${company.codeRangeEnd})';
                                        } else {
                                          displayText = '${company.name} (${company.code})';
                                        }
                                        return DropdownMenuItem<String?>(
                                          value: company.id, // Use company ID, not code
                                          child: Text(displayText),
                                        );
                                      }),
                                    ],
                                    onChanged: (String? value) async {
                                      setState(() {
                                        _selectedCompanyId = value;
                                        if (value == null) {
                                          _selectedCompanyCode = null;
                                          _companyCodeController.text = '';
                                        }
                                      });
                                      
                                      // If a company is selected, generate a random code within its range
                                      if (value != null && value.isNotEmpty) {
                                        final selectedCompany = _companies.firstWhere(
                                          (c) => c.id == value, // Match by company ID
                                          orElse: () => Company(id: '', code: '', name: ''),
                                        );
                                        
                                        if (selectedCompany.id.isNotEmpty && 
                                            selectedCompany.codeRangeStart != null && 
                                            selectedCompany.codeRangeEnd != null) {
                                          final generatedCode = await _companyService.generateCodeForCompanyAsync(selectedCompany.id);
                                          if (generatedCode != null && mounted) {
                                            setState(() {
                                              _selectedCompanyCode = generatedCode.toString();
                                              _companyCodeController.text = generatedCode.toString();
                                            });
                                          }
                                        }
                                      }
                                    },
                                    validator: (value) {
                                      // Company code is optional for admins
                                      if (_companyCodeController.text.isNotEmpty) {
                                        return _companyService.validateAdminCompanyCode(_companyCodeController.text);
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.keyboard),
                                  tooltip: 'Enter code manually',
                                  onPressed: _showManualCodeEntryDialog,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            FutureBuilder<Company?>(
                              future: () async {
                                final code = _companyCodeController.text.trim();
                                if (code.isEmpty) return null;
                                final codeValue = int.tryParse(code);
                                if (codeValue != null) {
                                  return await _companyService.getCompanyByCodeRange(codeValue);
                                }
                                return null;
                              }(),
                              builder: (context, snapshot) {
                                if (_selectedCompanyCode == null || _selectedCompanyCode!.isEmpty) {
                                  return Text(
                                    'Freelancer Admin - You will handle your own dispatches',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  );
                                }
                                final company = snapshot.data;
                                return Text(
                                  company != null
                                      ? 'Company Admin - You will be linked to ${company.name} (Code: $_selectedCompanyCode)'
                                      : 'Company Admin - Company code: $_selectedCompanyCode',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                  const SizedBox(height: 30),
                  _isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _signUp,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
