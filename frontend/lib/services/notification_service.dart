import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import '../utils/app_keys.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  // ── Alarm Sound Player ────────────────────────────────────────────────────
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;

  // ── Shared notification details ───────────────────────────────────────────
  static const NotificationDetails _alarmDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'travel_buddy_alarms_v2',
      'Travel Buddy Alarms',
      channelDescription: 'Critical travel reminders and alarms',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: 'Travel Buddy Alarm',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
    ),
  );

  Future<void> init() async {
    // ── 1. Timezone ───────────────────────────────────────────────────────────
    try {
      tz.initializeTimeZones();
      String? timeZoneName;
      try {
        timeZoneName = await FlutterTimezone.getLocalTimezone();
      } catch (e) {
        debugPrint('NotificationService: Could not get device timezone: $e');
      }
      try {
        tz.setLocalLocation(tz.getLocation(timeZoneName ?? 'UTC'));
        debugPrint(
            'NotificationService: Timezone set to "${timeZoneName ?? 'UTC'}"');
      } catch (e) {
        debugPrint(
            'NotificationService: Invalid timezone "$timeZoneName", using UTC.');
        tz.setLocalLocation(tz.getLocation('UTC'));
      }
    } catch (e) {
      debugPrint('NotificationService: Critical timezone error: $e');
    }

    // ── 2. Plugin init ────────────────────────────────────────────────────────
    await _notificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint(
            'NotificationService: Notification tapped — payload: ${details.payload}');
        
        // Show a visual dialog when the notification is received/tapped.
        // This ensures the user sees something even if the system banner is hidden.
        _showAlarmDialog(details.payload ?? 'Travel Reminder');
      },
      onDidReceiveBackgroundNotificationResponse: _backgroundHandler,
    );

    // ── 3. FIX: Consume stale app launch details ──────────────────────────────
    // On some Android versions, getNotificationAppLaunchDetails() returns a
    // stale "did notification launch app" result from a previous session.
    // If not consumed here, the plugin re-fires onDidReceiveNotificationResponse
    // immediately after initialize(), making it look like the alarm fired
    // instantly when it was actually just leftover state from last launch.
    try {
      final NotificationAppLaunchDetails? launchDetails =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        debugPrint(
            'NotificationService: Consumed stale launch notification — payload: ${launchDetails?.notificationResponse?.payload}');
      }
    } catch (e) {
      debugPrint(
          'NotificationService: Could not get launch details (non-fatal): $e');
    }

    // ── 4. Android permissions + channel ─────────────────────────────────────
    if (Platform.isAndroid) {
      final android = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (android == null) {
        debugPrint('NotificationService: FATAL — Android plugin is null.');
        return;
      }

      final bool? notifGranted =
          await android.requestNotificationsPermission();
      debugPrint(
          'NotificationService: Notification permission: $notifGranted');

      try {
        final bool? exactGranted =
            await android.requestExactAlarmsPermission();
        debugPrint(
            'NotificationService: Exact alarm permission: $exactGranted');
      } catch (e) {
        debugPrint(
            'NotificationService: Exact alarm permission error: $e');
      }

      // Channel v2 — fresh so old silent settings don't carry over
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          'travel_buddy_alarms_v2',
          'Travel Buddy Alarms',
          description: 'Critical travel reminders and alarms',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          showBadge: true,
          enableLights: true,
        ),
      );
      debugPrint('NotificationService: Channel created.');

      // ── 5. FIX: Check pending notifications on startup ──────────────────
      // This logs any already-scheduled alarms so we can verify they survived
      // a hot restart. If the list is empty after scheduling, the OS dropped them.
      try {
        final List<PendingNotificationRequest> pending =
            await _notificationsPlugin.pendingNotificationRequests();
        debugPrint(
            'NotificationService: ${pending.length} pending notification(s) on startup.');
        for (final p in pending) {
          debugPrint(
              '  → Pending ID: ${p.id}, title: "${p.title}", body: "${p.body}"');
        }
      } catch (e) {
        debugPrint(
            'NotificationService: Could not list pending notifications: $e');
      }
    }

    _isInitialized = true;
    debugPrint('NotificationService: ✅ Fully initialized.');
  }

  // ── Test notification ─────────────────────────────────────────────────────
  Future<void> showTestNotification() async {
    await showImmediateNotification(
      id: 99999,
      title: '✅ Alarm System Working',
      body: 'Notifications are configured correctly!',
    );
  }

  // ── Immediate notification ────────────────────────────────────────────────
  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      debugPrint(
          'NotificationService: Not initialized — skipping immediate notification.');
      return;
    }
    await _notificationsPlugin.show(id, title, body, _alarmDetails,
        payload: payload);
    debugPrint(
        'NotificationService: Immediate notification shown (ID: $id)');
  }

  // ── PRIMARY: Schedule using TZDateTime ────────────────────────────────────
  Future<void> scheduleNotificationTZ({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledTZDate,
    String? payload,
  }) async {
    if (!_isInitialized) {
      debugPrint(
          'NotificationService: Not initialized — cannot schedule "$title".');
      return;
    }

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    debugPrint('NotificationService: Now (TZ):       $now');
    debugPrint('NotificationService: Scheduled (TZ): $scheduledTZDate');

    if (scheduledTZDate.isBefore(now)) {
      debugPrint(
          'NotificationService: ⚠️ "$title" is in the past — skipping.');
      return;
    }

    await _doSchedule(id, title, body, scheduledTZDate, payload);

    // Confirm it was actually registered with AlarmManager
    try {
      final List<PendingNotificationRequest> pending =
          await _notificationsPlugin.pendingNotificationRequests();
      final bool registered = pending.any((p) => p.id == id);
      debugPrint(
          'NotificationService: Alarm registered with OS: $registered (${pending.length} total pending)');
    } catch (e) {
      debugPrint(
          'NotificationService: Could not verify pending notifications: $e');
    }
  }

  // ── LEGACY: Schedule using plain DateTime ─────────────────────────────────
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (!_isInitialized) {
      debugPrint(
          'NotificationService: Not initialized — cannot schedule "$title".');
      return;
    }
    if (scheduledDate.isBefore(DateTime.now())) {
      debugPrint(
          'NotificationService: ⚠️ "$title" is in the past — skipping.');
      return;
    }
    final tz.TZDateTime tzDate =
        tz.TZDateTime.from(scheduledDate, tz.local);
    await _doSchedule(id, title, body, tzDate, payload);
  }

  // ── Internal scheduling ───────────────────────────────────────────────────
  Future<void> _doSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduledTZDate,
    String? payload,
  ) async {
    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZDate,
        _alarmDetails,
        // alarmClock = same API as the built-in Clock app.
        // Cannot be suppressed by battery optimization or HiOS.
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
      debugPrint(
          'NotificationService: ✅ "$title" scheduled for $scheduledTZDate (ID: $id)');
    } catch (e) {
      debugPrint(
          'NotificationService: ❌ alarmClock schedule failed: $e');
      try {
        await _notificationsPlugin.zonedSchedule(
          id,
          title,
          body,
          scheduledTZDate,
          _alarmDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
        debugPrint(
            'NotificationService: ✅ "$title" scheduled (exactAllowWhileIdle fallback) (ID: $id)');
      } catch (e2) {
        try {
          await _notificationsPlugin.zonedSchedule(
            id,
            title,
            body,
            scheduledTZDate,
            _alarmDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: payload,
          );
          debugPrint(
              'NotificationService: ✅ "$title" scheduled (inexact fallback) (ID: $id)');
        } catch (e3) {
          debugPrint(
              'NotificationService: ❌ All schedule attempts failed: $e3');
        }
      }
    }
  }

  Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
    debugPrint('NotificationService: Cancelled notification ID $id');
  }

  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
    debugPrint('NotificationService: All notifications cancelled.');
  }

  void _showAlarmDialog(String message) {
    // ── Start Ringing (Bulletproof version) ──────────────────────────────────
    try {
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      
      // Use a faster, shorter MP3 (beeping)
      const String primaryUrl = 'https://www.soundjay.com/buttons/beep-07.mp3';
      const String fallbackUrl = 'https://actions.google.com/sounds/v1/alarms/digital_watch_alarm_long.ogg';

      // We wrap this in a future so any hanging network request doesn't block the UI
      Future.delayed(Duration.zero, () async {
        try {
          await _audioPlayer.play(UrlSource(primaryUrl)).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              debugPrint('NotificationService: Primary sound timed out, trying fallback.');
              return _audioPlayer.play(UrlSource(fallbackUrl));
            },
          );
          debugPrint('NotificationService: Sound triggered successfully.');
        } catch (inner) {
          debugPrint('NotificationService: Audio playing failed inside future: $inner');
          // SILENT FAIL (Crucial): Do not throw error here or app will crash
        }
      });
      
      debugPrint('NotificationService: Sound initialization triggered.');
    } catch (e) {
      debugPrint('NotificationService: Could not initialize sound player: $e');
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('NotificationService: Cannot show dialog — context is null.');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
             Icon(Icons.alarm, color: Color(0xFF6200EE), size: 30),
            SizedBox(width: 10),
            Text('ALARM RINGING'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_active, size: 60, color: Color(0xFF6200EE)),
            const SizedBox(height: 20),
            Text(message, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _stopAlarmSound();
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6200EE),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('DISMISS ALARM', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _stopAlarmSound() {
    try {
      _audioPlayer.stop();
      debugPrint('NotificationService: Sound stopped.');
    } catch (e) {
      debugPrint('NotificationService: Could not stop sound: $e');
    }
  }
}

// Must be top-level for background isolate support
@pragma('vm:entry-point')
void _backgroundHandler(NotificationResponse details) {
  debugPrint(
      'NotificationService [BG]: Tapped — payload: ${details.payload}');
}
