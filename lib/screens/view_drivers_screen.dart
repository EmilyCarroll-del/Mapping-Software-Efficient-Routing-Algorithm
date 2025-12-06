import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;

import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../services/profile_service.dart';
import '../widgets/drivers_list.dart';

class ViewDriversScreen extends StatelessWidget {
  const ViewDriversScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final firestoreService = FirestoreService();
    final profileService = ProfileService();

    void _removeDriverRole(String uid) {
      firestoreService.removeDriverRole(uid);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Drivers'),
      ),
      body: user == null
          ? const Center(child: Text('Please log in to see drivers.'))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active Drivers', style: Theme.of(context).textTheme.headlineSmall),
                  Expanded(
                    child: FutureBuilder<Map<String, dynamic>?>(
                      future: profileService.getProfile(user.uid, 'admin'),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final companyId = snapshot.data?['companyId'] as String?;

                        return DriversList(
                          driversStream: companyId != null && companyId.isNotEmpty
                              ? firestoreService.getDriversByCompany(companyId)
                              : firestoreService.getFreelanceDrivers(),
                          onRemoveDriver: _removeDriverRole,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
