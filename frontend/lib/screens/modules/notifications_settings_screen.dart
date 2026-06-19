import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

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
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'Notifications',
            subtitle: 'Choose what you want to be alerted about',
            onBack: () => Navigator.maybePop(context),
          ),
          if (!_loaded)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                    child: Text(
                      'Alert types',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        fontSize: 12.5,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  _toggleCard(
                    icon: Icons.alarm_rounded,
                    iconColor: AppColors.primary,
                    title: 'Reminders',
                    subtitle: 'Alerts for your scheduled reminders',
                    value: _reminderNotifications,
                    onChanged: (v) {
                      setState(() => _reminderNotifications = v);
                      _save('notif.reminders', v);
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _toggleCard(
                    icon: Icons.cloud_outlined,
                    iconColor: AppColors.infoBlue,
                    title: 'Travel Alerts',
                    subtitle: 'Weather, traffic and news updates',
                    value: _alertNotifications,
                    onChanged: (v) {
                      setState(() => _alertNotifications = v);
                      _save('notif.alerts', v);
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 10),
                  _toggleCard(
                    icon: Icons.payments_outlined,
                    iconColor: AppColors.warning,
                    title: 'Expense Prompts',
                    subtitle: 'Confirmation after voice expense logging',
                    value: _expenseNotifications,
                    onChanged: (v) {
                      setState(() => _expenseNotifications = v);
                      _save('notif.expenses', v);
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Reminder notifications require notification permission on your device.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _toggleCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
