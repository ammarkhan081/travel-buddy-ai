import 'package:intl/intl.dart';

class DateUtils {
  /// Robustly parses a datetime string from the backend, ensuring it is treated as UTC.
  /// If no timezone offset is present (e.g. Z or +00:00), it appends 'Z'.
  /// Returns a DateTime in the LOCAL timezone.
  static DateTime parseToLocal(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return DateTime.now();

    try {
      String normalized = dateStr.trim();
      // If no timezone/offset info, assume it's UTC (our backend standard)
      if (!normalized.contains('Z') && 
          !normalized.contains('+') && 
          !RegExp(r'-\d{2}:\d{2}$').hasMatch(normalized)) {
        normalized += 'Z';
      }
      
      return DateTime.parse(normalized).toLocal();
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Formats a datetime for dashboard display
  static String formatForDashboard(DateTime dt) {
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  /// Formats a datetime for the reminders list
  static String formatForReminders(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final reminderDate = DateTime(dt.year, dt.month, dt.day);

    if (reminderDate == today) {
      return 'Today, ${DateFormat('h:mm a').format(dt)}';
    } else if (reminderDate == today.add(const Duration(days: 1))) {
      return 'Tomorrow, ${DateFormat('h:mm a').format(dt)}';
    } else if (reminderDate.isBefore(today)) {
      return DateFormat('MMM dd, yyyy • h:mm a').format(dt);
    } else {
      return DateFormat('MMM dd • h:mm a').format(dt);
    }
  }
}

