import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  bool _reminderNotifications = true;
  bool _alertNotifications = true;
  bool _expenseNotifications = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _reminderNotifications = prefs.getBool('notif.reminders') ?? true;
      _alertNotifications = prefs.getBool('notif.alerts') ?? true;
      _expenseNotifications = prefs.getBool('notif.expenses') ?? false;
      _loaded = true;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'Notification Types',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Reminders'),
            subtitle: const Text('Alerts for your scheduled reminders'),
            value: _reminderNotifications,
            activeColor: theme.colorScheme.primary,
            onChanged: (v) {
              setState(() => _reminderNotifications = v);
              _save('notif.reminders', v);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Travel Alerts'),
            subtitle: const Text('Weather and traffic updates'),
            value: _alertNotifications,
            activeColor: theme.colorScheme.primary,
            onChanged: (v) {
              setState(() => _alertNotifications = v);
              _save('notif.alerts', v);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Expense Prompts'),
            subtitle: const Text('Confirmation prompts after voice expense logging'),
            value: _expenseNotifications,
            activeColor: theme.colorScheme.primary,
            onChanged: (v) {
              setState(() => _expenseNotifications = v);
              _save('notif.expenses', v);
            },
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Note: Reminder notifications require notification permissions to be granted on your device.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
