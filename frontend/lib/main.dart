import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fyp/screens/modules/feedback.dart';

import 'firebase_options.dart';
import 'widgets/auth_gate.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/home_page.dart';
import 'screens/home_dashboard.dart';

// Modules
import 'screens/modules/alerts_module.dart';
import 'screens/modules/voice_notes_module.dart';
import 'screens/modules/record_voice_note_screen.dart';
import 'screens/modules/diary_module.dart';
import 'screens/modules/edit_diary_entry.dart';
import 'screens/modules/profile_settings.dart';
import 'screens/modules/expense_tracker.dart';
import 'screens/modules/add_expense.dart';
import 'screens/modules/reminders_module.dart';
import 'screens/modules/add_reminder_voice.dart';
import 'screens/modules/add_reminder_manual.dart';
import 'screens/modules/chat_screen.dart';
import 'screens/modules/ai_settings_screen.dart';
import 'screens/modules/journey_history_screen.dart';
import 'screens/modules/emergency_contacts_screen.dart';
import 'screens/modules/start_journey_screen.dart';
import 'theme/themeprovider.dart';
import 'services/notification_service.dart';

import 'dart:async';
import 'utils/app_keys.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('MAIN: WidgetsBinding initialized.');

    runApp(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider()..loadTheme(),
        child: const MainEntryPoint(),
      ),
    );
  }, (error, stack) {
    debugPrint('MAIN CRITICAL ERROR: $error');
    debugPrint(stack.toString());
  });
}

class MainEntryPoint extends StatefulWidget {
  const MainEntryPoint({super.key});

  @override
  State<MainEntryPoint> createState() => _MainEntryPointState();
}

class _MainEntryPointState extends State<MainEntryPoint> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    // ── 1. Firebase ───────────────────────────────────────────────────────────
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('MAIN: Firebase initialized.');
    } catch (e) {
      try {
        await Firebase.initializeApp();
        debugPrint('MAIN: Firebase initialized (fallback).');
      } catch (e2) {
        debugPrint('MAIN: Firebase init failed: $e2');
      }
    }

    // ── 2. Notification Service (AWAITED — critical) ───────────────────────
    // Must be awaited so the service is fully ready before any screen
    // tries to schedule a notification. Without await, scheduling silently
    // fails because _isInitialized is still false.
    try {
      debugPrint('MAIN: Initializing NotificationService...');
      await NotificationService().init();
      debugPrint('MAIN: NotificationService ready.');
    } catch (e) {
      debugPrint('MAIN: NotificationService init failed: $e');
      // Continue anyway — app should still run even if notifications fail
    }

    // ── 3. Mark app as ready ──────────────────────────────────────────────────
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
          ),
        ),
      );
    }
    return const MyApp();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'FYP App',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: themeProvider.themeMode,
          initialRoute: '/',
          routes: {
            '/': (context) => const AuthGate(),
            '/splash': (context) => const SplashScreen(),
            '/onboarding': (context) => const OnboardingScreen(),
            '/login': (context) => const LoginScreen(),
            '/signup': (context) => const SignupScreen(),
            '/home': (context) => const HomePage(),
            '/dashboard': (context) => const HomeDashboard(),
            '/feedback': (context) => const FeedbackPage(),

            // Modules
            '/alerts': (context) => const AlertsModule(),
            '/voiceNotes': (context) => const VoiceNotesModule(),
            '/recordVoiceNote': (context) => const RecordVoiceNoteScreen(),
            '/diary': (context) => const DiaryModule(),
            '/editDiaryEntry': (context) => const EditDiaryEntry(),
            '/profileSettings': (context) => const ProfileSettings(),
            '/expenseTracker': (context) => const ExpenseTracker(),
            '/addExpense': (context) => const AddExpense(),
            '/reminders': (context) => const RemindersModule(),
            '/addReminderVoice': (context) => const AddReminderVoice(),
            '/addReminderManual': (context) => const AddReminderManual(),
            '/chat': (context) => const ChatScreen(),
            '/journeyHistory': (context) => const JourneyHistoryScreen(),
            '/emergencyContacts': (context) => const EmergencyContactsScreen(),
            '/startJourney': (context) => const StartJourneyScreen(),
            AiSettingsScreen.routeName: (context) => const AiSettingsScreen(),
          },
        );
      },
    );
  }
}
