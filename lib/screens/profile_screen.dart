import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../colors.dart';
import '../services/google_auth_service.dart';

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

  String? _profileImageUrl;
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;

  // GraphGo specific stats
  int _totalRoutes = 0;
  int _totalDeliveries = 0;
  double _totalDistance = 0.0;
  double _averageEfficiency = 0.0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserStats();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) {
        // Load user profile data from Firestore
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .get();

        if (userDoc.exists) {
          Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
          _nameController.text = userData['name'] ?? _user!.displayName ?? '';
          _phoneController.text = userData['phone'] ?? '';
          _bioController.text = userData['bio'] ?? '';
          _companyController.text = userData['company'] ?? '';
          _profileImageUrl = userData['profileImageUrl'];
        } else {
          // Create user profile if it doesn't exist
          _nameController.text = _user!.displayName ?? '';
          await _createUserProfile();
        }
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

  Future<void> _createUserProfile() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .set({
        'name': _user!.displayName ?? '',
        'email': _user!.email,
        'phone': '',
        'bio': '',
        'company': '',
        'profileImageUrl': _user!.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error creating user profile: $e');
    }
  }

  Future<void> _loadUserStats() async {
    try {
      if (_user != null) {
        // Load route optimization stats
        QuerySnapshot routesSnapshot = await FirebaseFirestore.instance
            .collection('routes')
            .where('userId', isEqualTo: _user!.uid)
            .get();

        int totalRoutes = routesSnapshot.docs.length;
        int totalDeliveries = 0;
        double totalDistance = 0.0;
        double totalEfficiency = 0.0;

        for (var doc in routesSnapshot.docs) {
          Map<String, dynamic> routeData = doc.data() as Map<String, dynamic>;
          totalDeliveries += (routeData['deliveryCount'] ?? 0) as int;
          totalDistance += (routeData['totalDistance'] ?? 0.0).toDouble();
          totalEfficiency += (routeData['efficiency'] ?? 0.0).toDouble();
        }

        if (mounted) {
          setState(() {
            _totalRoutes = totalRoutes;
            _totalDeliveries = totalDeliveries;
            _totalDistance = totalDistance;
            _averageEfficiency = totalRoutes > 0 ? totalEfficiency / totalRoutes : 0.0;
          });
        }
      }
    } catch (e) {
      print('Error loading user stats: $e');
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

  Future<void> _saveProfile() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Upload profile image if selected
      if (_selectedImageBytes != null) {
        await _uploadProfileImage();
      }

      // Save profile data to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .update({
        'name': _nameController.text,
        'phone': _phoneController.text,
        'bio': _bioController.text,
        'company': _companyController.text,
        if (_profileImageUrl != null) 'profileImageUrl': _profileImageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          "Profile",
          style: TextStyle(
            fontFamily: 'Impact',
            fontSize: 24,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
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
                                color: kPrimaryColor,
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

            // GraphGo Statistics
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.analytics, color: kPrimaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Route Optimization Stats',
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
                          'Routes',
                          _totalRoutes.toString(),
                          Icons.route,
                          kPrimaryColor,
                        ),
                        _buildStatCard(
                          'Deliveries',
                          _totalDeliveries.toString(),
                          Icons.local_shipping,
                          kAccentColor,
                        ),
                        _buildStatCard(
                          'Distance (km)',
                          _totalDistance.toStringAsFixed(1),
                          Icons.straighten,
                          Colors.orange,
                        ),
                        _buildStatCard(
                          'Efficiency',
                          '${_averageEfficiency.toStringAsFixed(1)}%',
                          Icons.trending_up,
                          Colors.green,
                        ),
                      ],
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

                    // Company
                    Row(
                      children: [
                        const Icon(Icons.business),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _isEditing
                              ? TextField(
                                  controller: _companyController,
                                  decoration: const InputDecoration(
                                    hintText: 'Enter company name',
                                    border: InputBorder.none,
                                  ),
                                )
                              : Text(
                                  _companyController.text.isNotEmpty
                                      ? _companyController.text
                                      : 'No company specified',
                                  style: TextStyle(
                                    color: _companyController.text.isEmpty
                                        ? Colors.grey[500]
                                        : null,
                                  ),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Route history coming soon!')),
                      );
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
                      side: BorderSide(color: kPrimaryColor),
                      foregroundColor: kPrimaryColor,
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
