import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final bool darkMode = settingsProvider.darkMode;

    final ThemeData currentTheme = Theme.of(context);
    final Color primaryTextColor = darkMode ? Colors.white : Colors.black87;
    final Color secondaryTextColor = darkMode ? Colors.grey[400]! : Colors.grey[600]!;
    final Color iconColor = darkMode ? Colors.white70 : Colors.black54;
    final Color sliderActiveColor = darkMode ? Colors.deepPurple.shade300 : Colors.deepPurple;
    final Color cardBackgroundColor = darkMode ? Colors.grey[850]! : currentTheme.cardColor;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2B0D),
        title: Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (authProvider.user != null)
            Card(
              color: cardBackgroundColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profile',
                      style: currentTheme.textTheme.titleLarge?.copyWith(color: primaryTextColor),
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(authProvider.user!.uid).get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                          return Text('Name: ${snapshot.data!['name']}', style: TextStyle(color: primaryTextColor));
                        }
                        return Text('Loading...', style: TextStyle(color: primaryTextColor));
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (authProvider.user != null)
            const SizedBox(height: 16),
          Card(
            color: cardBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: currentTheme.textTheme.titleLarge?.copyWith(color: primaryTextColor),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text('Dark Mode', style: TextStyle(color: primaryTextColor)),
                    subtitle: Text('Toggle dark theme', style: TextStyle(color: secondaryTextColor)),
                    value: darkMode,
                    onChanged: (value) {
                      settingsProvider.toggleDarkMode();
                    },
                    activeColor: sliderActiveColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: cardBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: currentTheme.textTheme.titleLarge?.copyWith(color: primaryTextColor),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.info, color: iconColor),
                    title: Text('Version', style: TextStyle(color: primaryTextColor)),
                    subtitle: Text('1.0.0', style: TextStyle(color: secondaryTextColor)),
                  ),
                  ListTile(
                    leading: Icon(Icons.code, color: iconColor),
                    title: Text('Built with Flutter', style: TextStyle(color: primaryTextColor)),
                    subtitle: Text('GraphGo - Graph Visualization App', style: TextStyle(color: secondaryTextColor)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
