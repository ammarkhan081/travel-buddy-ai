import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// flutter_svg was previously used; we now use a PNG asset instead

import '../theme/app_colors.dart';

/// Splash screen for Travio — animated blue/teal gradient + new brand logo.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _haloController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _logoController.forward();
    // Navigate to onboarding after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pushReplacementNamed(context, '/onboarding');
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _haloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppGradients.primary),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Pulsing halo + logo card
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _haloController,
                        builder: (_, _) {
                          final v = _haloController.value;
                          return Container(
                            width: 200 + v * 30,
                            height: 200 + v * 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                alpha: 0.18 * (1 - v),
                              ),
                            ),
                          );
                        },
                      ),
                      ScaleTransition(
                        scale: CurvedAnimation(
                          parent: _logoController,
                          curve: Curves.easeOutBack,
                        ),
                        child: Container(
                          width: 140,
                          height: 140,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo.png',
                            fit: BoxFit.contain,
                            semanticLabel: 'Travio Logo',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 50),
                  FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _logoController,
                      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Travio',
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2.0,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'YOUR SMART TRAVEL COMPANION',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}



