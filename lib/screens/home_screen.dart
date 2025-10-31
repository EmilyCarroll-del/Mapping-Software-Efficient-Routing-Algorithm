import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _handleLogout(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (BuildContext buildContext, Animation<double> animation, Animation<double> secondaryAnimation) {
        return Center(
          child: Material(
            borderRadius: BorderRadius.circular(15),
            child: Container(
              width: MediaQuery.of(context).size.width - 40,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Are you sure you want to logout?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      SizedBox(
                        width: 120,
                        child: ElevatedButton( // Changed to ElevatedButton
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade300, // Neutral background
                            foregroundColor: Colors.black87, // Darker text for contrast
                          ),
                          child: const Text('No', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: ElevatedButton(
                          onPressed: () {
                            final settings = Provider.of<SettingsProvider>(context, listen: false);
                            settings.logout();
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple.shade900,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Yes', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        );
      },
    );
  }

  Widget _buildStartDrivingButton(BuildContext context, bool darkMode) {
    return ElevatedButton(
      key: const ValueKey('startButton'),
      onPressed: () {
        Navigator.of(context).pushNamed('/login');
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple.shade900,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
        side: BorderSide(color: const Color(0xFF0D2B0D), width: darkMode ? 2 : 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        minimumSize: const Size(200, 60),
      ),
      child: const Text(
        'Start Driving',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLoggedInView(BuildContext context, bool darkMode) {
    return KeyedSubtree(
      key: const ValueKey('loggedInView'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushNamed('/map');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple.shade900,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              side: BorderSide(color: const Color(0xFF0D2B0D), width: darkMode ? 2 : 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              minimumSize: const Size(200, 60),
            ),
            child: const Text(
              'View Route',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsProvider, AuthProvider>(
      builder: (context, settings, auth, child) {
        final bool darkMode = settings.darkMode;
        final ThemeData currentTheme = Theme.of(context);

        final Color welcomeTextColor = darkMode ? Colors.white : Colors.black87;
        final Color sloganTextColor = darkMode ? Colors.grey[300]! : Colors.black54;
        final Color iconColor = darkMode ? Colors.white : const Color(0xFF0D2B0D);

        Widget currentActionArea;
        if (settings.isLoggedIn) {
          currentActionArea = _buildLoggedInView(context, darkMode);
        } else {
          currentActionArea = _buildStartDrivingButton(context, darkMode);
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF0D2B0D),
            leading: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white),
              onPressed: () => Navigator.of(context).pushNamed('/settings'),
            ),
            title: Consumer<AuthProvider>(builder: (context, auth, child) {
              return Text(
                'Welcome, ${auth.user?.displayName ?? 'Guest'}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              );
            }),
            centerTitle: true,
            actions: [
              if (settings.isLoggedIn)
                TextButton(
                  onPressed: () => _handleLogout(context),
                  style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16.0)),
                  child: const Row(
                    children: [
                      Text('Logout'),
                      SizedBox(width: 8),
                      Icon(Icons.logout, size: 18),
                    ],
                  ),
                ),
            ],
            toolbarHeight: kToolbarHeight + 20,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Transform.translate(
                  offset: const Offset(0, -15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Transform.translate(
                        offset: const Offset(0, -25),
                        child: Icon(
                          Icons.account_tree,
                          size: 100,
                          color: iconColor,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Welcome to GraphGo',
                        style: currentTheme.textTheme.headlineMedium?.copyWith(
                              fontSize: (currentTheme.textTheme.headlineMedium?.fontSize ?? 28) * 1.15,
                              fontWeight: FontWeight.bold,
                              color: welcomeTextColor,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Smarter routes, faster deliveries',
                        style: currentTheme.textTheme.bodyLarge?.copyWith(
                              fontSize: (currentTheme.textTheme.bodyLarge?.fontSize ?? 16) * 1.1,
                              color: sloganTextColor,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 70),
                Container(
                  height: 180,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                    },
                    child: currentActionArea,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
