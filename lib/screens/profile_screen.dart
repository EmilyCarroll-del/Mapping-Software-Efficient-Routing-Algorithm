import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import '../colors.dart';
import '../services/google_auth_service.dart';
import '../services/company_service.dart';
import '../services/profile_service.dart';
import '../services/code_assignment_service.dart';
import '../services/firestore_service.dart';
import '../models/company_model.dart';
import '../models/order.dart' as app_order;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? _user;
  bool _isLoading = false;
  bool _isEditing = false;
  final String _userRole = 'driver'; // Mobile app is always for drivers

  // Profile editing controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _companyCodeController = TextEditingController();
  
  String? _profileImageUrl;
  File? _selectedImage;
  
  final CompanyService _companyService = CompanyService();
  final ProfileService _profileService = ProfileService();
  final CodeAssignmentService _codeAssignmentService = CodeAssignmentService();
  final FirestoreService _firestoreService = FirestoreService();
  List<Company> _companies = [];
  String? _selectedCompanyCode;
  bool _loadingCompanies = false;

  // GraphGo specific stats
  int _totalRoutes = 0;
  int _totalDeliveries = 0;
  double _totalDistance = 0.0;
  double _averageEfficiency = 0.0;
  bool _statsLoading = false;
  String? _statsError;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserStats();
    _loadCompanies();
    
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null && mounted) {
        _loadUserStats();
      }
    });
  }

  Future<void> _loadCompanies() async {
    if (mounted) setState(() => _loadingCompanies = true);
    try {
      _companies = await _companyService.getAllCompanies();
      if (_selectedCompanyCode != null && _selectedCompanyCode!.isNotEmpty) {
        final companyExists = _companies.any((c) => c.code == _selectedCompanyCode);
        if (!companyExists) {
          final companyFromRange = await _companyService.getCompanyByCodeOrRange(_selectedCompanyCode!);
          if (companyFromRange == null) {
            _selectedCompanyCode = null;
            _companyCodeController.text = '';
          }
        }
      }
    } catch (e) {
      print('Error loading companies: $e');
      _selectedCompanyCode = null;
    } finally {
      if (mounted) setState(() => _loadingCompanies = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _companyCodeController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadUserStats();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) {
        // Mobile app always loads the 'driver' profile.
        final userData = await _profileService.getProfile(_user!.uid, _userRole);

        if (userData != null) {
          final firstName = userData['first_name'] ?? '';
          final lastName = userData['last_name'] ?? '';
          final name = userData['name'] ?? (firstName.isNotEmpty || lastName.isNotEmpty 
              ? '$firstName $lastName'.trim() 
              : _user!.displayName ?? '');
          
          _nameController.text = name;
          _phoneController.text = userData['phone'] ?? '';
          _bioController.text = userData['bio'] ?? '';
          final companyCode = userData['companyCode'] as String?;
          _companyCodeController.text = companyCode ?? '';
          _selectedCompanyCode = companyCode;
          _profileImageUrl = userData['profileImageUrl'] ?? userData['photo_url'];
          
          print('Profile loaded ($_userRole) - Company code: $companyCode');

        } else {
          // If no profile exists, create a driver profile by default.
          _nameController.text = _user!.displayName ?? '';
          await _createUserProfile();
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createUserProfile() async {
    try {
      await _profileService.createProfile(
        _user!.uid,
        'driver',
        {
          'first_name': _user!.displayName?.split(' ').first ?? '',
          'last_name': _user!.displayName?.split(' ').skip(1).join(' ') ?? '',
          'name': _user!.displayName ?? '',
          'email': _user!.email,
          'phone': '',
          'bio': '',
          'company': '',
          'profileImageUrl': _user!.photoURL,
          'photo_url': _user!.photoURL,
          'provider': 'email',
          'userType': 'driver',
          'role': 'Driver',
        },
      );
    } catch (e) {
      print('Error creating user profile: $e');
    }
  }

  Future<void> _loadUserStats() async {
    if (_user == null) return;
    
    if (mounted) {
      setState(() {
        _statsLoading = true;
        _statsError = null;
      });
    }
    
    // Initialize with empty values in case of errors
    int totalRoutes = 0;
    int totalDeliveries = 0;
    double totalDistance = 0.0;
    double averageEfficiency = 0.0;
    
    try {
      print('📊 Loading user stats for driver: ${_user!.uid}');
      
      // Use FirestoreService to get completed orders (same method Route History uses)
      List<app_order.Order> completedOrders = [];
      try {
        // The stream should emit data even if there are errors (it emits empty lists on error)
        // So we can safely use .first, but wrap it to handle any errors
        completedOrders = await _firestoreService
            .getDriverCompletedAddresses(_user!.uid)
            .timeout(const Duration(seconds: 10))
            .first
            .catchError((error) {
          print('❌ Stream error in getDriverCompletedAddresses: $error');
          if (error.toString().contains('permission-denied') || 
              error.toString().contains('Permission denied')) {
            _statsError = 'Permission denied: Cannot read orders';
          }
          return <app_order.Order>[]; // Return empty list on error
        });
        print('📦 Found ${completedOrders.length} completed orders (from FirestoreService)');
        if (completedOrders.isNotEmpty) {
          print('   Sample order ID: ${completedOrders.first.id}');
        }
      } catch (e) {
        print('❌ Error getting completed orders from FirestoreService: $e');
        print('   Error type: ${e.runtimeType}');
        print('   Error string: ${e.toString()}');
        if (e.toString().contains('permission-denied') || 
            e.toString().contains('Permission denied')) {
          _statsError = 'Permission denied: Cannot read orders';
        } else if (e.toString().contains('TimeoutException')) {
          print('   ⚠️ Timeout waiting for stream, continuing with empty list');
        } else {
          // If it's not a permission error, it might be a timeout or other issue
          print('   ⚠️ Non-permission error, continuing with empty list');
        }
        completedOrders = []; // Ensure we have an empty list
      }
      
      // Query route optimizations from user's subcollection (all routes, not just completed)
      // This should work since it's under the user's own document
      QuerySnapshot routeOptimizationsSnapshot;
      try {
        routeOptimizationsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .collection('routeOptimizations')
            .get();
        print('🗺️ Found ${routeOptimizationsSnapshot.docs.length} route optimizations');
        if (routeOptimizationsSnapshot.docs.isNotEmpty) {
          final sampleRoute = routeOptimizationsSnapshot.docs.first.data() as Map<String, dynamic>;
          print('   Sample route data keys: ${sampleRoute.keys.toList()}');
          print('   Sample route totalDistance: ${sampleRoute['totalDistance']}');
        }
      } catch (e) {
        print('❌ Error querying routeOptimizations collection: $e');
        if (e.toString().contains('permission-denied')) {
          _statsError = (_statsError != null ? '$_statsError. ' : '') + 'Cannot read routes';
        }
        // Create empty snapshot by querying a non-existent document - this will return empty
        try {
          routeOptimizationsSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc('temp-empty-${DateTime.now().millisecondsSinceEpoch}')
              .collection('routeOptimizations')
              .limit(1)
              .get();
        } catch (e2) {
          // If that fails too, just query the user's own collection with a filter that returns nothing
          // Use a field that exists but with a value that won't match anything
          routeOptimizationsSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(_user!.uid)
              .collection('routeOptimizations')
              .where('createdAt', isEqualTo: Timestamp.fromDate(DateTime(1970)))
              .limit(1)
              .get();
        }
      }
      
      // Also check legacy 'deliveries' collection for backward compatibility
      QuerySnapshot legacyDeliveriesSnapshot;
      try {
        legacyDeliveriesSnapshot = await FirebaseFirestore.instance
            .collection('deliveries')
            .where('driverId', isEqualTo: _user!.uid)
            .where('status', isEqualTo: 'completed')
            .get();
        print('📋 Found ${legacyDeliveriesSnapshot.docs.length} legacy completed deliveries');
      } catch (e) {
        print('❌ Error querying deliveries collection: $e');
        // Create empty snapshot - query for a non-existent driverId (valid field, just no matches)
        try {
          legacyDeliveriesSnapshot = await FirebaseFirestore.instance
              .collection('deliveries')
              .where('driverId', isEqualTo: 'temp-empty-${DateTime.now().millisecondsSinceEpoch}')
              .limit(1)
              .get();
        } catch (e2) {
          // If that fails, use a date filter that won't match anything
          legacyDeliveriesSnapshot = await FirebaseFirestore.instance
              .collection('deliveries')
              .where('createdAt', isEqualTo: Timestamp.fromDate(DateTime(1970)))
              .limit(1)
              .get();
        }
      }
      
      // Count total routes (from routeOptimizations - all routes, not just completed)
      int totalRoutes = routeOptimizationsSnapshot.docs.length;
      
      // Count total deliveries (from completed orders + legacy deliveries)
      int totalDeliveries = completedOrders.length + legacyDeliveriesSnapshot.docs.length;
      
      // Calculate total distance from completed orders
      double totalDistance = 0.0;
      for (var order in completedOrders) {
        // Try to get distance from the order's route optimization if available
        // For now, we'll need to check if the order has distance data stored
        // Since Order model doesn't have distance, we might need to query the original document
        // But for now, let's skip this and rely on routeOptimizations for distance
      }
      
      // Add distance from route optimizations (all routes, for total distance driven)
      for (var doc in routeOptimizationsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final distance = data['totalDistance'];
        if (distance != null) {
          final distValue = (distance is num) ? distance.toDouble() : 0.0;
          totalDistance += distValue;
          print('   Route ${doc.id}: distance = $distValue km');
        }
      }
      
      // Calculate efficiency from actual vs estimated duration
      // We need to get the actual order documents to access distance and duration
      double totalEfficiency = 0.0;
      int efficiencyCount = 0;
      
      // Query the actual order documents to get distance and duration data
      // Skip individual document queries if we already have permission errors to avoid more errors
      if (_statsError == null || !_statsError!.contains('permission-denied')) {
        for (var order in completedOrders) {
          try {
            DocumentSnapshot? orderDoc;
            if (order.sourceCollection == 'orders') {
              orderDoc = await FirebaseFirestore.instance
                  .collection('orders')
                  .doc(order.id)
                  .get();
            } else if (order.sourceCollection == 'addresses') {
              orderDoc = await FirebaseFirestore.instance
                  .collection('addresses')
                  .doc(order.id)
                  .get();
            }
            
            if (orderDoc != null && orderDoc.exists) {
              final data = orderDoc.data() as Map<String, dynamic>;
              
              // Get distance
              final distance = data['totalDistanceKm'];
              if (distance != null) {
                final distValue = (distance is num) ? distance.toDouble() : 0.0;
                totalDistance += distValue;
                print('   Order ${order.id}: distance = $distValue km');
              }
              
              // Get efficiency data
              final actualDuration = data['actualDurationSeconds'];
              final estimatedDuration = data['estimatedDurationSeconds'];
              
              if (actualDuration != null && estimatedDuration != null) {
                final actual = (actualDuration is num) ? actualDuration.toDouble() : 0.0;
                final estimated = (estimatedDuration is num) ? estimatedDuration.toDouble() : 0.0;
                
                if (actual > 0 && estimated > 0) {
                  final efficiency = (estimated / actual) * 100;
                  totalEfficiency += efficiency;
                  efficiencyCount++;
                  print('   Order ${order.id}: actual=${actual}s, estimated=${estimated}s, efficiency=${efficiency.toStringAsFixed(1)}%');
                }
              }
            }
          } catch (e) {
            print('   ⚠️ Error getting details for order ${order.id}: $e');
            if (e.toString().contains('permission-denied')) {
              _statsError = (_statsError != null ? '$_statsError. ' : '') + 'Cannot read order details';
              break; // Stop trying if we hit permission errors
            }
          }
        }
      } else {
        print('   ⚠️ Skipping individual order queries due to existing permission errors');
      }
      
      // Calculate average efficiency
      averageEfficiency = efficiencyCount > 0 
          ? (totalEfficiency / efficiencyCount).clamp(0.0, 200.0) // Cap at 200% for sanity
          : 0.0;
      
      print('✅ Stats calculated:');
      print('   Routes: $totalRoutes');
      print('   Deliveries: $totalDeliveries');
      print('   Distance: ${totalDistance.toStringAsFixed(2)} km');
      print('   Efficiency: ${averageEfficiency.toStringAsFixed(1)}% (from $efficiencyCount deliveries)');
      
      if (mounted) {
        setState(() {
          _totalRoutes = totalRoutes;
          _totalDeliveries = totalDeliveries;
          _totalDistance = totalDistance;
          _averageEfficiency = averageEfficiency;
          _statsLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('❌ Fatal error loading user stats: $e');
      print('❌ Stack trace: $stackTrace');
      // Set defaults on error
      if (mounted) {
        setState(() {
          _totalRoutes = 0;
          _totalDeliveries = 0;
          _totalDistance = 0.0;
          _averageEfficiency = 0.0;
          _statsLoading = false;
          _statsError = 'Failed to load stats: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);

      if (image != null && mounted) {
        setState(() => _selectedImage = File(image.path));
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error selecting image: $e')));
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_selectedImage == null) return;

    if (mounted) setState(() => _isLoading = true);
    try {
      String fileName = 'profile_${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference storageRef = FirebaseStorage.instance.ref().child('profile_images').child(fileName);

      UploadTask uploadTask = storageRef.putFile(_selectedImage!);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      if (mounted) setState(() => _profileImageUrl = downloadUrl);
      print('✅ Profile image uploaded: $downloadUrl');
    } catch (e) {
      print('Error uploading profile image: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading image: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showManualCodeEntryDialog() async {
    final result = await showDialog<String?>(
      context: context,
      builder: (BuildContext dialogContext) {
        final TextEditingController codeController = TextEditingController();
        final formKey = GlobalKey<FormState>();
        
        return AlertDialog(
          title: const Text('Enter Company Code'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 5,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Company Code',
                hintText: '12345',
                border: OutlineInputBorder(),
                counterText: '',
                helperText: 'Enter exactly 5 digits',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Please enter a company code';
                final trimmed = value.trim();
                if (trimmed.length != 5) return 'Code must be exactly 5 digits';
                if (!RegExp(r'^\d{5}$').hasMatch(trimmed)) return 'Code must contain only numbers';
                return null;
              },
              autofocus: true,
              onFieldSubmitted: (value) {
                if (formKey.currentState!.validate()) Navigator.of(dialogContext).pop(value.trim());
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(null), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.of(dialogContext).pop(codeController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    
    if (result != null && result.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedCompanyCode = result;
            _companyCodeController.text = result;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Company code set: $result'), backgroundColor: Colors.green));
        }
      });
    }
  }

  Future<void> _saveProfile() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      if (_selectedImage != null) await _uploadProfileImage();

      final nameParts = _nameController.text.trim().split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : '';
      final lastName = nameParts.length > 1 ? nameParts.skip(1).join(' ') : '';
      
      String? companyNameToSave;
      bool feedbackShown = false;

      if (_selectedCompanyCode != null && _selectedCompanyCode!.isNotEmpty) {
        try {
          final newAdminCode = await _codeAssignmentService.claimCode(code: _selectedCompanyCode!, driverId: _user!.uid);
          if (newAdminCode != null) {
            if(mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Code claimed successfully! You have joined the company.'), backgroundColor: Colors.green, duration: Duration(seconds: 3)),
            );
            feedbackShown = true;
          }
          
          final company = await _companyService.getCompanyByCodeOrRange(_selectedCompanyCode!);
          if (company != null) companyNameToSave = company.name;

        } catch (e) {
          if(mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Code warning: ${e.toString()}'), backgroundColor: Colors.orange, duration: const Duration(seconds: 3)),
          );
          final company = await _companyService.getCompanyByCodeOrRange(_selectedCompanyCode!);
          if (company != null) companyNameToSave = company.name;
        }
      }
      
      await _profileService.updateProfile(
        _user!.uid,
        _userRole, // This is now correctly hardcoded to 'driver' contextually
        {
          'first_name': firstName,
          'last_name': lastName,
          'name': _nameController.text,
          'phone': _phoneController.text,
          'bio': _bioController.text,
          'company': companyNameToSave,
          'companyCode': _selectedCompanyCode ?? '',
          if (_profileImageUrl != null) 'profileImageUrl': _profileImageUrl,
        },
      );

      if (!feedbackShown && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Profile updated successfully!'), backgroundColor: Colors.green));
      }

      if(mounted) setState(() => _isEditing = false);
      await _loadUserData();

    } catch (e) {
      print('Error saving profile: $e');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(title, style: TextStyle(fontSize: 12, color: color.withOpacity(0.7)), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Driver Profile'), backgroundColor: kPrimaryColor, foregroundColor: Colors.white),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text("Driver Profile", style: TextStyle(fontFamily: 'Impact', fontSize: 24, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
        actions: [
          if (_isEditing) IconButton(icon: const Icon(Icons.save), onPressed: _saveProfile, tooltip: 'Save Profile'),
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            onPressed: () {
              setState(() => _isEditing = !_isEditing);
              if (!_isEditing) _loadUserData(); else _loadCompanies();
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
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _isEditing ? _pickImage : null,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) : (_profileImageUrl != null ? NetworkImage(_profileImageUrl!) as ImageProvider : null),
                          child: _selectedImage == null && _profileImageUrl == null ? const Icon(Icons.person, size: 60) : null,
                        ),
                        if (_isEditing) Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: kPrimaryColor, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 20))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isEditing)
                    TextField(controller: _nameController, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Enter your name'))
                  else
                    Text(_nameController.text.isNotEmpty ? _nameController.text : 'User', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  Text(_user?.email ?? 'No email', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  FutureBuilder<Company?>(
                    future: _companyService.getCompanyByCodeOrRange(_companyCodeController.text.trim()),
                    builder: (context, snapshot) {
                      final companyCode = _companyCodeController.text.trim();
                      final isCompanyDriver = companyCode.isNotEmpty;
                      final company = snapshot.data;
                      String driverTypeText = isCompanyDriver ? (company != null ? 'Company Driver - ${company.name}' : 'Company Driver') : 'Freelance Driver';
                      Color indicatorColor = isCompanyDriver ? kPrimaryColor : Colors.orange;
                      IconData indicatorIcon = isCompanyDriver ? Icons.business : Icons.person_outline;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: indicatorColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: indicatorColor.withOpacity(0.3))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(indicatorIcon, size: 16, color: indicatorColor),
                            const SizedBox(width: 6),
                            Flexible(child: Text(driverTypeText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: indicatorColor), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.analytics, color: kPrimaryColor),
                            const SizedBox(width: 8),
                            const Text(
                              'Route Optimization Stats',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: _statsLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh),
                          onPressed: _statsLoading ? null : _loadUserStats,
                          tooltip: 'Refresh stats',
                          color: kPrimaryColor,
                        ),
                      ],
                    ),
                    if (_statsError != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[700], size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statsError!,
                                style: TextStyle(color: Colors.red[700], fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildStatCard('Routes', _totalRoutes.toString(), Icons.route, kPrimaryColor),
                        _buildStatCard('Deliveries', _totalDeliveries.toString(), Icons.local_shipping, kAccentColor),
                        _buildStatCard('Distance (km)', _totalDistance.toStringAsFixed(1), Icons.straighten, Colors.orange),
                        _buildStatCard('Efficiency', '${_averageEfficiency.toStringAsFixed(1)}%', Icons.trending_up, Colors.green),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Profile Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 16), Row(children: [const Icon(Icons.qr_code), const SizedBox(width: 8), Expanded(child: _isEditing ? _loadingCompanies ? const SizedBox(height: 48, child: Center(child: CircularProgressIndicator())) : Builder(builder: (context) {String? validValue; if (_selectedCompanyCode != null && _selectedCompanyCode!.isNotEmpty) {if (_companies.any((c) => c.code == _selectedCompanyCode)) validValue = _selectedCompanyCode;} return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: DropdownButton<String?>(value: validValue, isExpanded: true, hint: const Text('Select company (or leave blank)'), items: [const DropdownMenuItem<String?>(value: null, child: Text('None (Freelancer)')), ..._companies.map((company) => DropdownMenuItem<String?>(value: company.code, child: Text('${company.name} (${company.code})')))], onChanged: (String? value) => setState(() { _selectedCompanyCode = value; _companyCodeController.text = value ?? ''; }))), IconButton(icon: const Icon(Icons.keyboard), tooltip: 'Enter code manually', onPressed: _showManualCodeEntryDialog)]), const SizedBox(height: 4), FutureBuilder<Company?>(future: _companyService.getCompanyByCodeOrRange(_companyCodeController.text.trim()), builder: (context, snapshot) {final company = snapshot.data; final hasCode = _companyCodeController.text.trim().isNotEmpty; String message = hasCode ? (company != null ? 'Company driver - linked to ${company.name}' : 'Company driver - linked to company') : 'Freelance driver - can work with any admin'; return Text(message, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic));})]);}) : Builder(builder: (context) {final companyCode = _companyCodeController.text; if (companyCode.isEmpty) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('No company code', style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.bold)), Text('Freelance Driver - Can work with any admin', style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic))]); return FutureBuilder<Company?>(future: _companyService.getCompanyByCodeOrRange(companyCode), builder: (context, snapshot) {if (snapshot.connectionState == ConnectionState.waiting) return const Text('Loading...'); final company = snapshot.data; if (company != null) {return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${company.name} (${companyCode})', style: const TextStyle(fontWeight: FontWeight.bold)), Text('Company Driver - Linked to ${company.name}', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic))]);} else {return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Company Code: $companyCode', style: const TextStyle(fontWeight: FontWeight.bold)), Text('Company Driver - Linked via company code', style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic))]);}});}))]), const SizedBox(height: 16), Row(children: [const Icon(Icons.phone), const SizedBox(width: 8), Expanded(child: _isEditing ? TextField(controller: _phoneController, decoration: const InputDecoration(hintText: 'Enter phone number', border: InputBorder.none)) : Text(_phoneController.text.isNotEmpty ? _phoneController.text : 'No phone number', style: TextStyle(color: _phoneController.text.isEmpty ? Colors.grey[500] : null)))]), const SizedBox(height: 16), Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info), const SizedBox(width: 8), Expanded(child: _isEditing ? TextField(controller: _bioController, maxLines: 3, decoration: const InputDecoration(hintText: 'Tell us about yourself...', border: InputBorder.none)) : Text(_bioController.text.isNotEmpty ? _bioController.text : 'No bio added', style: TextStyle(color: _bioController.text.isEmpty ? Colors.grey[500] : null)))])]))),
            const SizedBox(height: 24),
            Row(children: [Expanded(child: ElevatedButton.icon(onPressed: () => context.go('/route-history'), icon: const Icon(Icons.history), label: const Text('Route History'), style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor, foregroundColor: Colors.white))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () async {await GoogleAuthService.signOut(); if (mounted) context.go('/');}, icon: const Icon(Icons.logout), label: const Text('Logout'), style: OutlinedButton.styleFrom(side: BorderSide(color: kPrimaryColor), foregroundColor: kPrimaryColor)))]),
          ],
        ),
      ),
    );
  }
}
