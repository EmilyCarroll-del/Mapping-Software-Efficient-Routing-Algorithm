import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../colors.dart';
import '../services/code_assignment_service.dart';
import '../services/profile_service.dart';

class MyDriversScreen extends StatefulWidget {
  const MyDriversScreen({super.key});

  @override
  _MyDriversScreenState createState() => _MyDriversScreenState();
}

class _MyDriversScreenState extends State<MyDriversScreen> {
  User? _user;
  bool _isLoading = false;
  bool _generatingCode = false;

  // Admin stats
  int _totalDrivers = 0;
  int _activeCodesCount = 0;
  int _claimedCodesCount = 0;
  double _companyReach = 0.0;

  // Drivers data
  List<Map<String, dynamic>> _linkedDrivers = [];
  List<Map<String, dynamic>> _allAdminCodes = [];
  String? _selectedCompanyId;

  final CodeAssignmentService _codeAssignmentService = CodeAssignmentService();
  final ProfileService _profileService = ProfileService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) {
        // Load admin profile to get company info
        final userData = await _profileService.getProfile(_user!.uid, 'admin');
        if (userData != null) {
          final companyCode = userData['companyCode'] as String?;
          if (companyCode != null && companyCode.isNotEmpty) {
            final codeValue = int.tryParse(companyCode);
            if (codeValue != null) {
              // We need company service to get company ID, but for now just load drivers
            }
          }
        }

        await _loadAdminCodesAndDrivers();
      }
    } catch (e) {
      print('Error loading data: $e');
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
        _totalDrivers = drivers.length;
        _activeCodesCount = activeCodes;
        _claimedCodesCount = claimedCodes;
        _companyReach = reach;
        _linkedDrivers = drivers;
      });
    } catch (e) {
      print('Error loading admin codes and drivers: $e');
    }
  }

  Future<void> _refreshData() async {
    await _loadAdminCodesAndDrivers();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Data refreshed'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _generateNewCode() async {
    if (_selectedCompanyId == null || _selectedCompanyId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a company first in your profile'),
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

        // Refresh data
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

  Future<void> _deleteDriver(Map<String, dynamic> driver) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Driver'),
        content: Text(
          'Are you sure you want to delete ${driver['name']}?\n\n'
          'This will:\n'
          '• Revoke their access code\n'
          '• Delete their driver profile\n'
          '• Remove all their data\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        // 1. Revoke the code assignment
        await _codeAssignmentService.revokeCode(code: driver['code']);

        // 2. Delete driver's profile
        await FirebaseFirestore.instance
            .collection('users')
            .doc('${driver['driverId']}_driver')
            .delete();

        // Close loading indicator
        if (mounted) {
          Navigator.of(context).pop();
        }

        // 3. Refresh
        await _refreshData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${driver['name']} has been deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('Error deleting driver: $e');
        
        // Close loading indicator if still open
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting driver: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Drivers'),
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
          "My Drivers",
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
            onPressed: _refreshData,
            tooltip: 'Refresh Drivers',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats Summary Card
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dashboard, color: kAdminGreen),
                        const SizedBox(width: 8),
                        const Text(
                          'Driver Management Overview',
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
                        Expanded(
                          child: _buildSummaryCard(
                            'Total Drivers',
                            _totalDrivers.toString(),
                            Icons.groups,
                            kAdminGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryCard(
                            'Active Codes',
                            _activeCodesCount.toString(),
                            Icons.vpn_key,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryCard(
                            'Claimed',
                            _claimedCodesCount.toString(),
                            Icons.check_circle,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Drivers List Section
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Linked Drivers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_linkedDrivers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.drive_eta, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No drivers linked yet',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Generate a code and share it with a driver to get started',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _linkedDrivers.length,
                        separatorBuilder: (context, index) => Divider(
                          color: Colors.grey[300],
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final driver = _linkedDrivers[index];
                          final claimedAt = driver['claimedAt'] as Timestamp?;
                          String dateText = '';
                          if (claimedAt != null) {
                            final date = claimedAt.toDate();
                            dateText = '${date.month}/${date.day}/${date.year}';
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 0,
                            ),
                            leading: CircleAvatar(
                              radius: 30,
                              backgroundImage: driver['profileImageUrl'] != null
                                  ? NetworkImage(driver['profileImageUrl'])
                                  : null,
                              child: driver['profileImageUrl'] == null
                                  ? const Icon(Icons.person, size: 28)
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    driver['name'] ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.green),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                if (driver['email'] != null &&
                                    driver['email'].toString().isNotEmpty)
                                  Row(
                                    children: [
                                      const Icon(Icons.email, size: 14),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          driver['email'],
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (driver['phone'] != null &&
                                    driver['phone'].toString().isNotEmpty)
                                  Row(
                                    children: [
                                      const Icon(Icons.phone, size: 14),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          driver['phone'],
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.qr_code, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Code: ${driver['code']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: kAdminGreen,
                                      ),
                                    ),
                                    if (dateText.isNotEmpty) ...[
                                      const SizedBox(width: 16),
                                      const Icon(Icons.calendar_today, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        dateText,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteDriver(driver),
                                  tooltip: 'Delete Driver',
                                ),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

