import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../colors.dart';
import '../models/delivery_address.dart';
import '../services/firestore_service.dart';
import '../services/code_assignment_service.dart';

class AdminRouteHistoryScreen extends StatefulWidget {
  const AdminRouteHistoryScreen({super.key});

  @override
  State<AdminRouteHistoryScreen> createState() => _AdminRouteHistoryScreenState();
}

class _AdminRouteHistoryScreenState extends State<AdminRouteHistoryScreen> {
  final CodeAssignmentService _codeAssignmentService = CodeAssignmentService();
  final FirestoreService _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _linkedDrivers = [];
  Map<String, List<DeliveryAddress>> _driverRoutes = {};
  bool _isLoading = true;
  String? _selectedDriverId;
  String? _selectedFilterDriverId; // Filter by specific driver

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
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get all linked drivers
        _linkedDrivers = await _codeAssignmentService.getAdminDrivers(user.uid);
        print('Route History: Found ${_linkedDrivers.length} linked drivers');

        // Get completed addresses for all drivers
        if (_linkedDrivers.isNotEmpty) {
          final driverIds = _linkedDrivers.map((d) => d['driverId'] as String).toList();
          print('Route History: Fetching completed addresses for ${driverIds.length} drivers');
          
          final allAddresses = await _firestoreService.getAllDriversCompletedAddresses(driverIds);
          print('Route History: Found ${allAddresses.length} completed addresses total');

          // Group by driver
          _driverRoutes = {};
          for (final address in allAddresses) {
            final driverId = address.driverId;
            if (driverId != null && driverId.isNotEmpty) {
              if (!_driverRoutes.containsKey(driverId)) {
                _driverRoutes[driverId] = [];
              }
              _driverRoutes[driverId]!.add(address);
            }
          }
          
          print('Route History: Grouped into ${_driverRoutes.length} drivers with routes');
          _driverRoutes.forEach((driverId, routes) {
            print('  Driver $driverId: ${routes.length} routes');
          });
        } else {
          print('Route History: No linked drivers found');
        }
      }
    } catch (e) {
      print('Error loading route history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading route history: $e'),
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

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  int get _totalRoutes {
    return _driverRoutes.values.fold(0, (sum, routes) => sum + routes.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kAdminGreen,
        foregroundColor: Colors.white,
        title: const Text(
          "Route History",
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
            onPressed: _loadData,
            tooltip: 'Refresh Routes',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _linkedDrivers.isEmpty
              ? _buildEmptyState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Card
                      Card(
                        elevation: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.summarize, color: kAdminGreen),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Overview',
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
                                      'Total Routes',
                                      _totalRoutes.toString(),
                                      Icons.route,
                                      kAdminGreen,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildSummaryCard(
                                      'Active Drivers',
                                      _linkedDrivers.length.toString(),
                                      Icons.groups,
                                      Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Filter Section
                      if (_linkedDrivers.isNotEmpty && _driverRoutes.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              'Filter: ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('All Drivers'),
                              selected: _selectedFilterDriverId == null,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedFilterDriverId = null;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_linkedDrivers.length > 1)
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: _linkedDrivers.map((driver) {
                                final driverId = driver['driverId'] as String;
                                final driverName = driver['name'] ?? 'Unknown';
                                final routeCount = _driverRoutes[driverId]?.length ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text('$driverName ($routeCount)'),
                                    selected: _selectedFilterDriverId == driverId,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedFilterDriverId = driverId;
                                        });
                                      }
                                    },
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],

                      // Drivers Routes
                      if (_selectedDriverId == null)
                        ..._buildFilteredDriversView()
                      else
                        ..._buildSingleDriverView(_selectedDriverId!),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No drivers linked yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Link drivers in your profile to see their route history',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFilteredDriversView() {
    // Filter drivers based on selected filter
    final driversToShow = _selectedFilterDriverId == null
        ? _linkedDrivers
        : _linkedDrivers.where((d) => d['driverId'] == _selectedFilterDriverId).toList();
    
    return [
      Text(
        _selectedFilterDriverId == null ? 'All Drivers' : 'Filtered Results',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      ...driversToShow.map((driver) {
        final driverId = driver['driverId'] as String;
        final routes = _driverRoutes[driverId] ?? [];
        final driverName = driver['name'] ?? 'Unknown';

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 3,
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundImage: driver['profileImageUrl'] != null
                  ? NetworkImage(driver['profileImageUrl'])
                  : null,
              child: driver['profileImageUrl'] == null
                  ? const Icon(Icons.person)
                  : null,
            ),
            title: Text(
              driverName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${routes.length} completed route${routes.length == 1 ? '' : 's'}'),
            trailing: routes.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'NO ROUTES',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kAdminGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kAdminGreen),
                    ),
                    child: Text(
                      '${routes.length}',
                      style: TextStyle(
                        color: kAdminGreen,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
            children: routes.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: Text(
                          'No completed routes yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                  ]
                : routes.map((route) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kAdminGreen.withOpacity(0.1),
                        child: Icon(Icons.location_on, color: kAdminGreen),
                      ),
                      title: Text(route.fullAddress),
                      subtitle: Text('Completed • ${_formatDate(route.createdAt)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 16),
                        onPressed: () {
                          setState(() {
                            _selectedDriverId = driverId;
                          });
                        },
                      ),
                    );
                  }).toList(),
          ),
        );
      }),
      if (_selectedDriverId != null)
        ElevatedButton(
          onPressed: () {
            setState(() {
              _selectedDriverId = null;
            });
          },
          child: const Text('Show All Drivers'),
        ),
    ];
  }

  List<Widget> _buildSingleDriverView(String driverId) {
    final driver = _linkedDrivers.firstWhere(
      (d) => d['driverId'] == driverId,
      orElse: () => {'name': 'Unknown', 'profileImageUrl': null},
    );
    final routes = _driverRoutes[driverId] ?? [];
    final driverName = driver['name'] ?? 'Unknown';

    return [
      GestureDetector(
        onTap: () {
          setState(() {
            _selectedDriverId = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.arrow_back, color: kAdminGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  driverName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (routes.isEmpty)
        Center(
          child: Column(
            children: [
              Icon(Icons.history, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No completed routes yet',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        )
      else
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: routes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final route = routes[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: kAdminGreen.withOpacity(0.1),
                child: Icon(Icons.location_on, color: kAdminGreen),
              ),
              title: Text(route.fullAddress),
              subtitle: Text('Completed • ${_formatDate(route.createdAt)}'),
            );
          },
        ),
    ];
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

