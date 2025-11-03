import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    // Navigate to the home screen after a delay
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        context.go('/');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B3D2F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeTransition(
              opacity: _animation,
              child: Text(
                'GraphGo',
                style: GoogleFonts.lobster(
                  fontSize: 72,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 40),
            AnimatedTextKit(
              animatedTexts: [
                TyperAnimatedText(
                  '🚚 . . . . . .',
                  textStyle: const TextStyle(
                    fontSize: 28,
                    color: Colors.white,
                  ),
                  speed: const Duration(milliseconds: 200),
                ),
              ],
              repeatForever: true,
            ),
          ],
        ),
      ),
    );
  }
}
