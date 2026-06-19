import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Checks and requests the two Android permissions that the [alarm] package
/// needs to ring reliably:
///
///  1. **SCHEDULE_EXACT_ALARM** — Android 12+ (API 31+) requires explicit
///     user approval via Settings > Apps > Special app access > Alarms &
///     reminders.  Without it, [AlarmManager.setExactAndAllowWhileIdle]
///     throws a [SecurityException] that the plugin silently swallows →
///     alarm is scheduled but never fires.
///
///  2. **Ignore battery optimisation** — Samsung One UI and most OEM ROMs
///     aggressively kill background services.  Exempting the app prevents
///     the foreground AlarmService from being terminated before it can ring.
///
/// Call [ensurePermissions] once when the user first opens a reminder screen.
class AlarmPermissionHelper {
  /// Checks both permissions and requests / guides the user if either is
  /// missing.  Safe to call multiple times — exits immediately on iOS or if
  /// both permissions are already granted.
  static Future<void> ensurePermissions(BuildContext context) async {
    if (!Platform.isAndroid) return;

    await _handleExactAlarm(context);
    if (context.mounted) await _handleBatteryOptimization(context);
  }

  // ── Exact-alarm permission ──────────────────────────────────────────────────

  static Future<void> _handleExactAlarm(BuildContext context) async {
    PermissionStatus status = await Permission.scheduleExactAlarm.status;
    if (status.isGranted) return;

    // On Android 12+ this opens the "Alarms & reminders" special-access page.
    status = await Permission.scheduleExactAlarm.request();
    if (status.isGranted) return;

    // Still not granted — show a dialog so the user knows alarms won't ring.
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text('⏰', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('Enable Alarms', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          'Your reminders need the "Alarms & Reminders" permission to ring on '
          'time — even when the phone is idle.\n\n'
          'Tap Open Settings, then toggle ON this app.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ── Battery-optimisation exemption ─────────────────────────────────────────

  static Future<void> _handleBatteryOptimization(BuildContext context) async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) return;

    // Show a brief explanation before the system dialog appears.
    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Text('🔋', style: TextStyle(fontSize: 22)),
            SizedBox(width: 8),
            Text('Background Activity', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          'Allow this app to run in the background so alarms ring even when '
          'the screen is off or the app is closed.\n\n'
          'Samsung users: also go to\n'
          'Settings → Apps → [App] → Battery → Unrestricted.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  /// Quick check — returns [true] if the exact-alarm permission is granted.
  /// Used before scheduling to decide whether to warn the user.
  static Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    return await Permission.scheduleExactAlarm.isGranted;
  }
}
