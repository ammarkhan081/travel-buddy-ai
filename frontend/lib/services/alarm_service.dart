import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Schedules and cancels real device alarms via the [alarm] package.
///
/// Unlike flutter_local_notifications (which only plays a short notification
/// sound), the alarm package uses Android's AlarmManager / iOS's local
/// notifications to ring continuously — even when the app is killed.
///
/// ⚠️  REQUIRED PERMISSIONS on Android:
///   - SCHEDULE_EXACT_ALARM must be granted by the user at runtime (Android 12+).
///     Without it AlarmManager.setExactAndAllowWhileIdle() throws a
///     SecurityException that the plugin silently swallows → alarm appears
///     scheduled but never fires.  Call [AlarmPermissionHelper.ensurePermissions]
///     before scheduling to guide the user.
///   - Battery optimisation must be disabled so the foreground service is not
///     killed by the OS before the alarm time.
class AlarmService {
  /// Returns true if the device can schedule exact alarms.
  /// Always true on iOS and on Android < 12.
  static Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    return await Permission.scheduleExactAlarm.isGranted;
  }

  /// Schedule an alarm to ring at [scheduledDate].
  ///
  /// [id]    — unique int per reminder; use:
  ///             tzScheduled.millisecondsSinceEpoch.remainder(2000000000).toInt()
  /// [title] — shown in the system notification and on the ring screen.
  /// [body]  — the reminder text (e.g. "Flight to Skardu").
  static Future<void> set({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    // Guard: on Android 12+ the exact-alarm permission must be granted at
    // runtime.  The alarm package silently swallows the SecurityException so
    // the alarm appears scheduled but never rings.  Log a warning here so it's
    // visible in the debug console.
    if (Platform.isAndroid) {
      final granted = await canScheduleExactAlarms();
      if (!granted) {
        debugPrint(
          'AlarmService: ⚠️  SCHEDULE_EXACT_ALARM NOT granted — '
          'alarm ID $id will NOT ring! '
          'Call AlarmPermissionHelper.ensurePermissions(context) first.',
        );
      }
    }

    try {
      await Alarm.set(
        alarmSettings: AlarmSettings(
          id: id,
          dateTime: scheduledDate,
          // Audio file bundled with the app — declared in pubspec.yaml assets
          assetAudioPath: 'assets/alarm.mp3',
          loopAudio: true,
          vibrate: true,
          volume: 0.9,
          // Fade in over 3 seconds so it is not jarring
          fadeDuration: 3.0,
          // Show a warning notification if the user kills the app before alarm fires
          warningNotificationOnKill: true,
          // Show full-screen alarm UI (wakes screen on Android)
          androidFullScreenIntent: true,
          notificationSettings: NotificationSettings(
            title: title,
            body: body,
            // System notification action button that stops the alarm immediately
            stopButton: 'Dismiss',
          ),
        ),
      );
      debugPrint('AlarmService: ✅ "$body" set for $scheduledDate (ID: $id)');
    } catch (e) {
      debugPrint('AlarmService: ❌ Failed to set alarm "$body": $e');
      rethrow;
    }
  }

  /// Cancel an alarm that was previously set with [id].
  static Future<void> cancel(int id) async {
    try {
      await Alarm.stop(id);
      debugPrint('AlarmService: Cancelled alarm ID $id');
    } catch (e) {
      debugPrint('AlarmService: Error cancelling alarm $id: $e');
    }
  }

  /// Cancel every scheduled alarm in one call.
  static Future<void> cancelAll() async {
    try {
      await Alarm.stopAll();
      debugPrint('AlarmService: All alarms cancelled');
    } catch (e) {
      debugPrint('AlarmService: Error cancelling all alarms: $e');
    }
  }
}
