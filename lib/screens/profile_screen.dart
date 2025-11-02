import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../colors.dart';
import '../services/google_auth_service.dart';
import '../services/company_service.dart';
import '../services/profile_service.dart';
import '../services/code_assignment_service.dart';
import '../services/seed_companies.dart';
import '../models/company_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  bool _isLoading = false;
  bool _isEditing = false;

  // Profile editing controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _companyCodeController = TextEditingController();

  String? _profileImageUrl;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;

  final CompanyService _companyService = CompanyService();
  final ProfileService _profileService = ProfileService();
  final CodeAssignmentService _codeAssignmentService = CodeAssignmentService();
  List<Company> _companies = [];
  String? _selectedCompanyId; // Store company ID when selected
  String? _selectedCompanyCode; // Store generated code
  String? _selectedCompanyName; // Store company name for display
  bool _loadingCompanies = false;
  bool _generatingCode = false;

  // Admin Dashboard Stats
  int _totalDrivers = 0;
  int _activeCodesCount = 0;
  int _claimedCodesCount = 0;
  double _companyReach = 0.0;

  // My Drivers section
  List<Map<String, dynamic>> _linkedDrivers = [];
  List<Map<String, dynamic>> _allAdminCodes = [];
  int _activeCodeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadCompanies();
  }

  Future<void> _loadCompanies() async {
    setState(() => _loadingCompanies = true);
    try {
      _companies = await _companyService.getAllCompanies();
      
      // If no companies exist, seed them
      if (_companies.isEmpty) {
        print('No companies found, seeding companies...');
        final seeder = CompanySeeder();
        await seeder.seedCompanies();
        _companies = await _companyService.getAllCompanies();
      }
      
      if (_selectedCompanyCode != null && _selectedCompanyCode!.isNotEmpty) {
        final companyExists = _companies.any((c) => c.code == _selectedCompanyCode);
        if (!companyExists) {
          _selectedCompanyCode = null;
          _companyCodeController.text = '';
        }
      }
      setState(() => _loadingCompanies = false);
    } catch (e) {
      print('Error loading companies: $e');
      _selectedCompanyCode = null;
      setState(() => _loadingCompanies = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _companyController.dispose();
    _companyCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) {
        // Load admin profile data from separate document: users/{uid}_admin
        final userData = await _profileService.getProfile(_user!.uid, 'admin');

        if (userData != null) {
          // Get name from first_name + last_name or name field or email
          final firstName = userData['first_name'] ?? '';
          final lastName = userData['last_name'] ?? '';
          final name = userData['name'] ?? 
                      (firstName.isNotEmpty || lastName.isNotEmpty 
                          ? '$firstName $lastName'.trim() 
                          : _user!.displayName ?? _user!.email?.split('@')[0] ?? '');
          
          _nameController.text = name;
          _phoneController.text = userData['phone'] ?? '';
          _bioController.text = userData['bio'] ?? '';
          _companyController.text = userData['company'] ?? '';
          final companyCode = userData['companyCode'] as String?;
          
          // Check if stored code is still available, if not get current available code
          String? codeToDisplay = companyCode;
          if (companyCode != null && companyCode.isNotEmpty) {
            final isAvailable = await _codeAssignmentService.isCodeAvailable(companyCode);
            if (!isAvailable) {
              // Code was claimed, get current available code
              codeToDisplay = await _codeAssignmentService.getAdminCurrentCode(_user!.uid);
              // Update profile with new code if found
              if (codeToDisplay != null) {
                await _profileService.updateProfile(
                  _user!.uid,
                  'admin',
                  {'companyCode': codeToDisplay},
                );
              }
            }
          } else {
            // No code stored, try to get current available code
            codeToDisplay = await _codeAssignmentService.getAdminCurrentCode(_user!.uid);
          }
          
          _companyCodeController.text = codeToDisplay ?? '';
          _selectedCompanyCode = codeToDisplay;
          
          // Try to identify which company this code belongs to
          if (codeToDisplay != null && codeToDisplay.isNotEmpty) {
            final codeValue = int.tryParse(codeToDisplay);
            if (codeValue != null) {
              final company = await _companyService.getCompanyByCodeRange(codeValue);
              if (company != null) {
                _selectedCompanyId = company.id;
                _selectedCompanyName = company.name;
                _companyController.text = company.name;
              }
            }
          }
          
          _profileImageUrl = userData['profileImageUrl'] ?? userData['photo_url'];
        } else {
          // Create admin profile if it doesn't exist
          _nameController.text = _user!.displayName ?? _user!.email?.split('@')[0] ?? '';
          await _createUserProfile();
        }
        
        // Load all admin codes and linked drivers
        await _loadAdminCodesAndDrivers();
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadAdminCodesAndDrivers() async {
    if (_user == null) return;
    
    try {
      // Load all admin codes
      final adminCodes = await _codeAssignmentService.getAdminCodes(_user!.uid);
      
      // Load linked drivers
      final drivers = await _codeAssignmentService.getAdminDrivers(_user!.uid);
      
      // Calculate admin dashboard stats
      final activeCodes = adminCodes.where((c) => c['status'] == 'available').length;
      final claimedCodes = adminCodes.where((c) => c['status'] == 'claimed').length;
      final totalCodes = adminCodes.length;
      final reach = totalCodes > 0 ? (claimedCodes / totalCodes * 100) : 0.0;
      
      setState(() {
        _allAdminCodes = adminCodes;
        _activeCodeCount = activeCodes;
        _linkedDrivers = drivers;
        _totalDrivers = drivers.length;
        _activeCodesCount = activeCodes;
        _claimedCodesCount = claimedCodes;
        _companyReach = reach;
      });
      
      print('Profile: Loaded ${drivers.length} drivers, ${activeCodes} active codes, ${claimedCodes} claimed codes');
    } catch (e) {
      print('Error loading admin codes and drivers: $e');
    }
  }

  Future<void> _createUserProfile() async {
    try {
      // Create admin profile in separate document: users/{uid}_admin
      final nameParts = (_user!.displayName ?? _user!.email?.split('@')[0] ?? 'User').split(' ');
      await _profileService.createProfile(
        _user!.uid,
        'admin',
        {
          'first_name': nameParts.isNotEmpty ? nameParts.first : '',
          'last_name': nameParts.length > 1 ? nameParts.skip(1).join(' ') : '',
          'name': _user!.displayName ?? _user!.email?.split('@')[0] ?? 'User',
          'email': _user!.email,
          'phone': '',
          'bio': '',
          'company': '',
          'profileImageUrl': _user!.photoURL,
          'photo_url': _user!.photoURL,
          'provider': 'email',
          'userType': 'admin',
          'role': 'Admin',
        },
      );
    } catch (e) {
      print('Error creating user profile: $e');
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImage = image;
          _selectedImageBytes = bytes;
        });
      }
    } catch (e) {
      print('Error picking image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_selectedImage == null || _selectedImageBytes == null) return;

    try {
      setState(() {
        _isLoading = true;
      });

      String fileName = 'profile_${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child(fileName);

      UploadTask uploadTask = storageRef.putData(_selectedImageBytes!); 
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _profileImageUrl = downloadUrl;
        });
      }

      print('✅ Profile image uploaded: $downloadUrl');
    } catch (e) {
      print('Error uploading profile image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
              style: ElevatedButton.styleFrom(
                backgroundColor: kAdminGreen,
                foregroundColor: Colors.white,
              ),
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
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Company code set: $result'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _loadUserData();
      await _loadAdminCodesAndDrivers();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile refreshed'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('Error refreshing profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error refreshing profile: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generateNewCode() async {
    if (_selectedCompanyId == null || _selectedCompanyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a company first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _generatingCode = true;
    });
    
    try {
      final newCode = await _codeAssignmentService.generateNewCodeForAdmin(
        adminId: _user!.uid,
        companyId: _selectedCompanyId!,
      );
      
      if (newCode != null && mounted) {
        setState(() {
          _generatingCode = false;
        });
        
        // Refresh profile to show new code
        await _loadAdminCodesAndDrivers();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New code generated: $newCode'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          _generatingCode = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to generate code'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _generatingCode = false;
      });
      
      print('Error generating new code: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating code: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Upload profile image if selected
      if (_selectedImageBytes != null) {
        await _uploadProfileImage();
      }

      // Save admin profile data to separate document: users/{uid}_admin
      final nameParts = _nameController.text.trim().split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName = nameParts.length > 1 ? nameParts.skip(1).join(' ') : '';
      
      // Create code assignment if company is selected and code is generated
      if (_selectedCompanyId != null && _selectedCompanyCode != null && _selectedCompanyCode!.isNotEmpty) {
        try {
          await _codeAssignmentService.createCodeAssignment(
            adminId: _user!.uid,
            companyId: _selectedCompanyId!,
            code: _selectedCompanyCode!,
          );
        } catch (e) {
          print('Error creating code assignment: $e');
          // Continue with profile save even if assignment creation fails
        }
      }
      
      await _profileService.updateProfile(
        _user!.uid,
        'admin',
        {
          'first_name': firstName,
          'last_name': lastName,
          'name': _nameController.text,
          'phone': _phoneController.text,
          'bio': _bioController.text,
          'company': _selectedCompanyName ?? _companyController.text,
          'companyCode': _selectedCompanyCode ?? '',
          'companyId': _selectedCompanyId,
          if (_profileImageUrl != null) 'profileImageUrl': _profileImageUrl,
        },
      );

      if (mounted) {
        setState(() {
          _isEditing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error saving profile: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {VoidCallback? onTap}) {
    final cardContent = Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    return Expanded(
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: cardContent,
              ),
            )
          : cardContent,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Profile'),
          backgroundColor: kAdminGreen,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kAdminGreen,
        foregroundColor: Colors.white,
        title: const Text(
          "Admin Profile",
          style: TextStyle(
            fontFamily: 'Impact',
            fontSize: 24,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshProfile,
            tooltip: 'Refresh Profile',
          ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveProfile,
              tooltip: 'Save Profile',
            ),
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
                if (!_isEditing) {
                  _selectedImage = null;
                  _selectedImageBytes = null;
                  _loadUserData();
                } else {
                  // Reload companies when entering edit mode
                  _loadCompanies();
                }
              });
            },
            tooltip: _isEditing ? 'Cancel Edit' : 'Edit Profile',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Center(
              child: Column(
                children: [
                  // Profile Image
                  GestureDetector(
                    onTap: _isEditing ? _pickImage : null,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: _selectedImageBytes != null
                              ? MemoryImage(_selectedImageBytes!)
                              : (_profileImageUrl != null
                                  ? NetworkImage(_profileImageUrl!) as ImageProvider
                                  : null),
                          child: _selectedImageBytes == null && _profileImageUrl == null
                              ? const Icon(Icons.person, size: 60)
                              : null,
                        ),
                        if (_isEditing)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: kAdminGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // User Name
                  if (_isEditing)
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Enter your name',
                      ),
                    )
                  else
                    Text(
                      _nameController.text.isNotEmpty ? _nameController.text : 'User',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                  // User Email
                  Text(
                    _user?.email ?? 'No email',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Admin Dashboard Statistics
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.dashboard, color: kAdminGreen),
                        const SizedBox(width: 8),
                        const Text(
                          'Admin Dashboard Stats',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        _buildStatCard(
                          'Total Drivers',
                          _totalDrivers.toString(),
                          Icons.groups,
                          kAdminGreen,
                        ),
                        _buildStatCard(
                          'Active Codes',
                          _activeCodesCount.toString(),
                          Icons.vpn_key,
                          Colors.blue,
                          onTap: () {
                            Navigator.of(context).pushNamed('/active-codes');
                          },
                        ),
                        _buildStatCard(
                          'Claimed Codes',
                          _claimedCodesCount.toString(),
                          Icons.check_circle,
                          Colors.orange,
                        ),
                        _buildStatCard(
                          'Company Reach',
                          '${_companyReach.toStringAsFixed(1)}%',
                          Icons.trending_up,
                          Colors.purple,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Navigate to My Drivers page button
                    if (_selectedCompanyId != null && _selectedCompanyId!.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pushNamed('/my-drivers');
                        },
                        icon: const Icon(Icons.groups),
                        label: const Text('Manage My Drivers'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kAdminGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Profile Details
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Helper banner to guide users to edit mode
                    if (!_isEditing && (_selectedCompanyCode == null || _selectedCompanyCode!.isEmpty))
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_outline, color: Colors.amber[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '👆 Click the edit icon above to select your company and get your unique code',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.amber[900],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Company Selection (OPTIONAL for admin users)
                    // When admin selects company, code is auto-generated
                    Row(
                      children: [
                        const Icon(Icons.business),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _isEditing
                              ? _loadingCompanies
                                  ? const SizedBox(
                                      height: 48,
                                      child: Center(child: CircularProgressIndicator()),
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        DropdownButton<String?>(
                                          value: _selectedCompanyId,
                                          isExpanded: true,
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
                                                value: company.id,
                                                child: Text(displayText),
                                              );
                                            }),
                                          ],
                                          onChanged: (String? companyId) async {
                                            setState(() {
                                              _selectedCompanyId = companyId;
                                              if (companyId == null) {
                                                _selectedCompanyCode = null;
                                                _selectedCompanyName = null;
                                                _companyCodeController.text = '';
                                                _companyController.text = '';
                                              } else {
                                                _generatingCode = true;
                                              }
                                            });

                                            // Generate code when company is selected
                                            if (companyId != null && companyId.isNotEmpty) {
                                              final selectedCompany = _companies.firstWhere(
                                                (c) => c.id == companyId,
                                                orElse: () => Company(id: '', code: '', name: ''),
                                              );

                                              if (selectedCompany.id.isNotEmpty &&
                                                  selectedCompany.codeRangeStart != null &&
                                                  selectedCompany.codeRangeEnd != null) {
                                                try {
                                                  final generatedCode = await _companyService.generateCodeForCompanyAsync(selectedCompany.id);
                                                  if (generatedCode != null && mounted) {
                                                    setState(() {
                                                      _selectedCompanyCode = generatedCode.toString();
                                                      _selectedCompanyName = selectedCompany.name;
                                                      _companyCodeController.text = generatedCode.toString();
                                                      _companyController.text = selectedCompany.name;
                                                      _generatingCode = false;
                                                    });

                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Generated code: $generatedCode for ${selectedCompany.name}'),
                                                        backgroundColor: Colors.green,
                                                        duration: const Duration(seconds: 2),
                                                      ),
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (mounted) {
                                                    setState(() => _generatingCode = false);
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Error generating code: $e'),
                                                        backgroundColor: Colors.red,
                                                      ),
                                                    );
                                                  }
                                                }
                                              }
                                            }
                                          },
                                        ),
                                        if (_generatingCode)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 8.0),
                                            child: LinearProgressIndicator(),
                                          ),
                                        const SizedBox(height: 8),
                                        if (_selectedCompanyCode != null && _selectedCompanyCode!.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.all(8.0),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.qr_code, size: 16, color: Colors.blue),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        'Your Code: ${_selectedCompanyCode}',
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      Text(
                                                        'Share this code with drivers',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.grey[600],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        const SizedBox(height: 4),
                                        FutureBuilder<Company?>(
                                          future: () async {
                                            if (_selectedCompanyCode == null || _selectedCompanyCode!.isEmpty) {
                                              return null;
                                            }
                                            final codeValue = int.tryParse(_selectedCompanyCode!);
                                            if (codeValue != null) {
                                              return await _companyService.getCompanyByCodeRange(codeValue);
                                            }
                                            return null;
                                          }(),
                                          builder: (context, snapshot) {
                                            final company = snapshot.data;
                                            String message = _selectedCompanyCode == null || _selectedCompanyCode!.isEmpty
                                                ? 'Freelancer admin - handle your own dispatches'
                                                : (company != null
                                                    ? 'Company Admin - ${company.name}'
                                                    : 'Company Admin - linked to company');
                                            return Text(
                                              message,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedCompanyName ?? (_companyController.text.isNotEmpty ? _companyController.text : 'No company selected'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _selectedCompanyName == null && _companyController.text.isEmpty
                                            ? Colors.grey[500]
                                            : null,
                                      ),
                                    ),
                                    if (_selectedCompanyCode != null && _selectedCompanyCode!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.all(6.0),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Code: ${_selectedCompanyCode}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      _selectedCompanyCode == null || _selectedCompanyCode!.isEmpty
                                          ? 'Freelancer Admin - Handle your own dispatches'
                                          : (_selectedCompanyName != null
                                              ? 'Company Admin - $_selectedCompanyName'
                                              : 'Company Admin - Linked via company code'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Phone Number
                    Row(
                      children: [
                        const Icon(Icons.phone),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _isEditing
                              ? TextField(
                                  controller: _phoneController,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter phone number',
                                    border: InputBorder.none,
                                  ),
                                )
                              : Text(
                                  _phoneController.text.isNotEmpty
                                      ? _phoneController.text
                                      : 'No phone number',
                                  style: TextStyle(
                                    color: _phoneController.text.isEmpty
                                        ? Colors.grey[500]
                                        : null,
                                  ),
                                ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Bio
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _isEditing
                              ? TextField(
                                  controller: _bioController,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    hintText: 'Tell us about yourself...',
                                    border: InputBorder.none,
                                  ),
                                )
                              : Text(
                                  _bioController.text.isNotEmpty
                                      ? _bioController.text
                                      : 'No bio added',
                                  style: TextStyle(
                                    color: _bioController.text.isEmpty
                                        ? Colors.grey[500]
                                        : null,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/admin-route-history');
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('Route History'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      // Logout functionality
                      await GoogleAuthService.signOut();
                      if (mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: kAdminGreen),
                      foregroundColor: kAdminGreen,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
