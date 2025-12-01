import 'dart:async';
import 'package:flutter/material.dart';

/// Full-screen loading overlay styled like your original
/// "Generating Route..." screen, with animated truck + animated dots.
///
/// Usage:
///   LoadingOverlay.show(
///     context,
///     message: 'Generating Route',
///     subMessage: 'Optimizing delivery path for you',
///   );
///
///   // later...
///   LoadingOverlay.hide(context);
class LoadingOverlay {
  static OverlayEntry? _currentEntry;

  /// Show the overlay. If it's already showing, this is a no-op.
  static void show(
      BuildContext context, {
        String message = 'Generating Route',
        String? subMessage,
      }) {
    if (_currentEntry != null) return; // already visible

    _currentEntry = OverlayEntry(
      builder: (ctx) => _FullScreenLoadingView(
        message: message,
        subMessage: subMessage,
      ),
    );

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      _currentEntry = null;
      return;
    }
    overlay.insert(_currentEntry!);
  }

  /// Hide the overlay if it is currently visible.
  static void hide(BuildContext context) {
    if (_currentEntry != null) {
      _currentEntry!.remove();
      _currentEntry = null;
    }
  }
}

class _FullScreenLoadingView extends StatefulWidget {
  final String message;
  final String? subMessage;

  const _FullScreenLoadingView({
    Key? key,
    required this.message,
    this.subMessage,
  }) : super(key: key);

  @override
  State<_FullScreenLoadingView> createState() => _FullScreenLoadingViewState();
}

class _FullScreenLoadingViewState extends State<_FullScreenLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _bounceAnimation;

  Timer? _dotsTimer;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();

    // Truck bounce animation (up/down)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    // Animated dots after the message
    _dotsTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      setState(() {
        _dotCount = (_dotCount + 1) % 4; // 0,1,2,3 -> then back to 0
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _dotsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0D2B0D);

    final dots = '.' * _dotCount;

    return Material(
      color: backgroundColor,
      child: SafeArea(
        child: Stack(
          children: [
            // Centered animated truck + text
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _bounceAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _bounceAnimation.value),
                        child: child,
                      );
                    },
                    child: const Text(
                      '🚚',
                      style: TextStyle(fontSize: 64),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${widget.message}$dots',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.subMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.subMessage!,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            // Spinner near the bottom
            const Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
