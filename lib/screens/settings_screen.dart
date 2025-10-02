import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart'; // Import SettingsProvider

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // State variables for graph visualization have been removed

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final bool darkMode = settingsProvider.darkMode;

    final ThemeData currentTheme = Theme.of(context);
    // Colors will now be primarily driven by MaterialApp's theme/darkTheme
    // but we can still make specific overrides or use theme colors directly.

    final Color primaryTextColor = darkMode ? Colors.white : Colors.black87;
    final Color secondaryTextColor = darkMode ? Colors.grey[400]! : Colors.grey[600]!;
    final Color iconColor = darkMode ? Colors.white70 : Colors.black54;
    final Color sliderActiveColor = darkMode ? Colors.deepPurple.shade300 : Colors.deepPurple;
    final Color cardBackgroundColor = darkMode ? Colors.grey[850]! : currentTheme.cardColor;

    return Scaffold(
      // Scaffold background color will be handled by MaterialApp theme
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D2B0D),
        title: const Text(
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
                    value: darkMode, // Use value from provider
                    onChanged: (value) {
                      settingsProvider.toggleDarkMode(); // Call provider method
                    },
                    activeColor: sliderActiveColor,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // The "Graph Visualization" card has been completely removed.
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

  // _showColorPicker method has been removed as it's no longer needed.
}
