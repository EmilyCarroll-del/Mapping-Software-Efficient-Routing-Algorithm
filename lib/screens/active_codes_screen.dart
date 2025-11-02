import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../colors.dart';
import '../services/code_assignment_service.dart';

class ActiveCodesScreen extends StatefulWidget {
  const ActiveCodesScreen({super.key});

  @override
  State<ActiveCodesScreen> createState() => _ActiveCodesScreenState();
}

class _ActiveCodesScreenState extends State<ActiveCodesScreen> {
  final CodeAssignmentService _codeAssignmentService = CodeAssignmentService();
  List<Map<String, dynamic>> _allCodes = [];
  bool _isLoading = true;
  String? _selectedFilter = 'all'; // all, available, claimed

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final codes = await _codeAssignmentService.getAdminCodes(user.uid);
        setState(() {
          _allCodes = codes;
        });
      }
    } catch (e) {
      print('Error loading codes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading codes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteCode(String code) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Code'),
        content: Text(
          'Are you sure you want to delete code $code?\n\nThis action cannot be undone.',
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
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        await FirebaseFirestore.instance.collection('code_assignments').doc(code).delete();

        if (mounted) Navigator.of(context).pop();

        await _loadCodes();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Code $code has been deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('Error deleting code: $e');
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting code: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _reassignCode(String code, String currentDriverId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reassign Code'),
        content: Text('This will revoke code $code from the current driver.\n\nThe code will become available again for assignment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reassign'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        await _codeAssignmentService.revokeCode(code: code);

        if (mounted) Navigator.of(context).pop();

        await _loadCodes();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Code $code has been reassigned'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('Error reassigning code: $e');
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error reassigning code: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  List<Map<String, dynamic>> get _filteredCodes {
    if (_selectedFilter == 'available') {
      return _allCodes.where((c) => c['status'] == 'available').toList();
    } else if (_selectedFilter == 'claimed') {
      return _allCodes.where((c) => c['status'] == 'claimed').toList();
    }
    return _allCodes;
  }

  int get _availableCount => _allCodes.where((c) => c['status'] == 'available').length;
  int get _claimedCount => _allCodes.where((c) => c['status'] == 'claimed').length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kAdminGreen,
        foregroundColor: Colors.white,
        title: const Text("Active Codes Management", style: TextStyle(fontFamily: 'Impact', fontSize: 24, fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCodes,
            tooltip: 'Refresh Codes',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(children: [const Icon(Icons.vpn_key, color: kAdminGreen), const SizedBox(width: 8), const Text('Codes Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
                          const SizedBox(height: 16),
                          Row(children: [
                            Expanded(child: _buildSummaryCard('Total', _allCodes.length.toString(), Icons.list, kAdminGreen)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildSummaryCard('Available', _availableCount.toString(), Icons.vpn_key, Colors.blue)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildSummaryCard('Claimed', _claimedCount.toString(), Icons.check_circle, Colors.orange)),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(children: [
                    const Text('Filter: ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('All'), selected: _selectedFilter == 'all', onSelected: (selected) { if (selected) setState(() => _selectedFilter = 'all'); }),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('Available'), selected: _selectedFilter == 'available', onSelected: (selected) { if (selected) setState(() => _selectedFilter = 'available'); }),
                    const SizedBox(width: 8),
                    ChoiceChip(label: const Text('Claimed'), selected: _selectedFilter == 'claimed', onSelected: (selected) { if (selected) setState(() => _selectedFilter = 'claimed'); }),
                  ]),
                  const SizedBox(height: 16),
                  if (_filteredCodes.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(children: [Icon(Icons.vpn_key_off, size: 64, color: Colors.grey[400]), const SizedBox(height: 16), Text('No codes found', style: TextStyle(color: Colors.grey[600], fontSize: 16))]),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filteredCodes.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final codeData = _filteredCodes[index];
                        final code = codeData['code'] as String;
                        final status = codeData['status'] as String;
                        final driverId = codeData['driverId'] as String?;
                        final createdAt = codeData['createdAt'] as Timestamp?;
                        final claimedAt = codeData['claimedAt'] as Timestamp?;

                        String dateText = '';
                        if (createdAt != null) {
                          final date = createdAt.toDate();
                          dateText = '${date.month}/${date.day}/${date.year}';
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(backgroundColor: status == 'available' ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1), child: Icon(status == 'available' ? Icons.vpn_key : Icons.check_circle, color: status == 'available' ? Colors.blue : Colors.orange)),
                            title: Row(children: [
                              Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: status == 'available' ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: status == 'available' ? Colors.blue : Colors.orange)),
                                child: Text(status.toUpperCase(), style: TextStyle(color: status == 'available' ? Colors.blue : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ]),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                if (dateText.isNotEmpty) Row(children: [const Icon(Icons.calendar_today, size: 14), const SizedBox(width: 4), Text('Created: $dateText', style: const TextStyle(fontSize: 12))]),
                                if (status == 'claimed' && claimedAt != null) Row(children: [const Icon(Icons.check, size: 14), const SizedBox(width: 4), Text('Claimed: ${claimedAt.toDate().month}/${claimedAt.toDate().day}/${claimedAt.toDate().year}', style: const TextStyle(fontSize: 12))]),
                                if (driverId != null) Row(children: [const Icon(Icons.person, size: 14), const SizedBox(width: 4), Text('Driver ID: ${driverId.substring(0, 8)}...', style: const TextStyle(fontSize: 12))]),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'delete') _deleteCode(code);
                                if (value == 'reassign' && driverId != null) _reassignCode(code, driverId);
                              },
                              itemBuilder: (context) => [
                                if (status == 'claimed' && driverId != null) const PopupMenuItem(value: 'reassign', child: Row(children: [Icon(Icons.swap_horiz, size: 18), SizedBox(width: 8), Text('Reassign')])),
                                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(children: [Icon(icon, color: color, size: 28), const SizedBox(height: 8), Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)), Text(title, style: TextStyle(fontSize: 12, color: color.withOpacity(0.7), fontWeight: FontWeight.w500), textAlign: TextAlign.center)]),
    );
  }
}

