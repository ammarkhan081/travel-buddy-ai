import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../services/fastapi_service.dart';
import '../../services/notification_service.dart';
import '../../utils/ui_utils.dart';
import 'add_reminder_manual.dart';
import 'add_reminder_voice.dart';
import '../../utils/date_utils.dart' as fyp_date;

class RemindersModule extends StatefulWidget {
  const RemindersModule({super.key});

  @override
  State<RemindersModule> createState() => _RemindersModuleState();
}

class _RemindersModuleState extends State<RemindersModule> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // KEY FIX: Use the same ID calculation as add_reminder_manual.dart
  // so that cancel() actually cancels the correct scheduled notification.
  int _notificationIdFromDateTime(DateTime dt) {
    final tz.TZDateTime tzDt = tz.TZDateTime.from(dt, tz.local);
    return tzDt.millisecondsSinceEpoch.remainder(2000000000).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Reminders')),
        body: const Center(child: Text('Please log in to view reminders')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        backgroundColor: const Color(0xFF1E66F5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: FastApiService().get('/api/reminders/').then((res) => res as List<dynamic>),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.alarm_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No reminders yet',
                          style: TextStyle(
                              fontSize: 18, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create your first reminder below',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                // Sort by date/time ascending (using robust local parsing)
                final reminders = snapshot.data!.toList()
                  ..sort((a, b) {
                    final aDate = fyp_date.DateUtils.parseToLocal(a['datetime']);
                    final bDate = fyp_date.DateUtils.parseToLocal(b['datetime']);
                    return aDate.compareTo(bDate);
                  });

                return ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: reminders.length,
                  itemBuilder: (context, index) {
                    final data = reminders[index];
                    return _buildReminderCard(context, data['id'].toString(), data);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const AddReminderVoice()),
                      );
                      if (result == true) setState(() {});
                    },
                    icon: const Icon(Icons.mic),
                    label: const Text('Voice'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const AddReminderManual()),
                      );
                      if (result == true) setState(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Manual'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E66F5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderCard(
      BuildContext context, String docId, Map<String, dynamic> data) {
    final String title = data['title'] ?? 'Untitled';
    final bool completed = data['status'] == 'completed';
    final String? dateStr = data['datetime'];
    final DateTime? reminderDateTime =
        dateStr != null ? fyp_date.DateUtils.parseToLocal(dateStr) : null;

    String timeText = 'No date set';
    if (dateStr != null) {
      final localDateTime = fyp_date.DateUtils.parseToLocal(dateStr);
      timeText = fyp_date.DateUtils.formatForReminders(localDateTime);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        leading: Checkbox(
          value: completed,
          onChanged: (value) =>
              _toggleReminder(docId, data, !completed),
          activeColor: const Color(0xFF1E66F5),
        ),
        title: Text(
          title,
          style: TextStyle(
            decoration:
                completed ? TextDecoration.lineThrough : TextDecoration.none,
            color: completed ? Colors.grey : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(timeText),
            if (reminderDateTime != null &&
                reminderDateTime.isBefore(DateTime.now()) &&
                !completed)
              const Text(
                'Overdue',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteReminder(docId, data),
        ),
      ),
    );
  }

  Future<void> _toggleReminder(
      String docId, Map<String, dynamic> data, bool completed) async {
    try {
      await FastApiService().put('/api/reminders/$docId', {
        'status': completed ? 'completed' : 'pending',
      });
      
      setState(() {});

      // Only cancel notification when marking as DONE
      if (completed) {
        final String? dateStr = data['datetime'];
        final DateTime? reminderDateTime =
            dateStr != null ? fyp_date.DateUtils.parseToLocal(dateStr) : null;
        if (reminderDateTime != null) {
          final int notificationId =
              _notificationIdFromDateTime(reminderDateTime);
          await NotificationService().cancelNotification(notificationId);
          debugPrint(
              'RemindersModule: Cancelled notification ID $notificationId on toggle.');
        }
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error updating reminder: $e', isError: true);
      }
    }
  }

  Future<void> _deleteReminder(
      String docId, Map<String, dynamic> data) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reminder'),
        content:
            const Text('Are you sure you want to delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FastApiService().delete('/api/reminders/$docId');

        final String? dateStr = data['datetime'];
        final DateTime? reminderDateTime =
            dateStr != null ? fyp_date.DateUtils.parseToLocal(dateStr) : null;
        if (reminderDateTime != null) {
          final int notificationId =
              _notificationIdFromDateTime(reminderDateTime);
          await NotificationService().cancelNotification(notificationId);
          debugPrint(
              'RemindersModule: Cancelled notification ID $notificationId on delete.');
        }

        if (mounted) {
          UIFeedback.showSnackBar(context, 'Reminder deleted');
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          UIFeedback.showSnackBar(context, 'Error deleting reminder: $e', isError: true);
        }
      }
    }
  }
}
