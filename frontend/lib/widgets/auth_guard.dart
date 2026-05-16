import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/login_screen.dart';

/// AuthGuard - A mixin/helper class for route protection
class AuthGuard {
  /// Check if user is currently authenticated
  static bool isAuthenticated() {
    return FirebaseAuth.instance.currentUser != null;
  }

  /// Get current user
  static User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  /// Navigate to login if not authenticated
  static void requireAuth(BuildContext context) {
    if (!isAuthenticated()) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  /// Check authentication and execute callback
  static void checkAuth(BuildContext context, VoidCallback onAuthenticated) {
    if (isAuthenticated()) {
      onAuthenticated();
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }
}

/// RouteGuard - A widget that guards routes based on authentication
class RouteGuard extends StatelessWidget {
  final Widget child;
  final bool requireAuth;
  final Widget? fallbackWidget;

  const RouteGuard({
    super.key,
    required this.child,
    this.requireAuth = true,
    this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (!requireAuth) {
      return child;
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data != null) {
          return child;
        }

        return fallbackWidget ?? const LoginScreen();
      },
    );
  }
}

