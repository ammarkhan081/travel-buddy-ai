import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../screens/home_page.dart';

/// AuthGate - A widget that acts as an authentication gate
/// It checks if user is authenticated and shows appropriate screen
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show splash screen while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        // If user is logged in, show home page
        if (snapshot.hasData && snapshot.data != null) {
          return const HomePage();
        }

        // If user is not logged in, show login screen
        return const LoginScreen();
      },
    );
  }
}

/// ProtectedRoute - A wrapper widget to protect individual routes
/// Usage: Wrap any widget with ProtectedRoute to require authentication
class ProtectedRoute extends StatelessWidget {
  final Widget child;
  final Widget? loadingWidget;
  final Widget? unauthenticatedWidget;

  const ProtectedRoute({
    super.key,
    required this.child,
    this.loadingWidget,
    this.unauthenticatedWidget,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading widget while checking
        if (snapshot.connectionState == ConnectionState.waiting) {
          return loadingWidget ?? const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // If user is authenticated, show the protected content
        if (snapshot.hasData && snapshot.data != null) {
          return child;
        }

        // If user is not authenticated, show login screen or custom widget
        return unauthenticatedWidget ?? const LoginScreen();
      },
    );
  }
}

