import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../services/alarm_service.dart';
import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart' as fyp_date;
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';
import 'add_reminder_manual.dart';
import 'add_reminder_voice.dart';

/// Reminders module — list / complete / delete reminders, plus voice + manual
/// quick-add. Visuals match the dashboard's purple language.
class RemindersModule extends StatefulWidget {
  const RemindersModule({super.key});

  @override
  State<RemindersModule> createState() => _RemindersModuleState();
}

class _RemindersModuleState extends State<RemindersModule> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String _filter = 'all'; // 'all' | 'today' | 'overdue' | 'upcoming' | 'done'

  /// Same ID derivation as `add_reminder_manual.dart` so cancel() targets the
  /// notification that was originally scheduled.
  int _notificationIdFromDateTime(DateTime dt) {
    final tz.TZDateTime tzDt = tz.TZDateTime.from(dt, tz.local);
    return tzDt.millisecondsSinceEpoch.remainder(2000000000).toInt();
  }

  /// Loads reminders and re-arms local alarms for any future, still-pending
  /// reminder. Local alarms are device-only and are lost on reinstall / new
  /// device, so we reconcile them from the server each time this screen opens.
  /// Best-effort: alarm failures never block showing the list.
  Future<List<dynamic>> _loadAndRescheduleReminders() async {
    final res = await FastApiService().get('/api/reminders/');
    final list = (res is List) ? res : <dynamic>[];
    final now = DateTime.now();
    for (final item in list) {
      if (item is! Map) continue;
      final data = Map<String, dynamic>.from(item);
      final status = (data['status'] ?? 'pending').toString();
      if (status != 'pending') continue;
      final dt = fyp_date.DateUtils.parseToLocal(
        (data['datetime'] ?? '').toString(),
      );
      if (!dt.isAfter(now)) continue;
      try {
        await AlarmService.set(
          id: _notificationIdFromDateTime(dt),
          title: 'Travel Reminder ⏰',
          body: (data['title'] ?? 'Reminder').toString(),
          scheduledDate: dt,
        );
      } catch (_) {}
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final theme = Theme.of(context);

    if (user == null) {
      return Scaffold(
        body: Column(
          children: [
            AppHeader(
              title: 'Reminders',
              subtitle: 'Sign in to view your reminders',
              onBack: () => Navigator.maybePop(context),
            ),
            const Expanded(
              child: Center(child: Text('Please log in to view reminders')),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'Reminders',
            subtitle: 'Stay on track for every trip',
            onBack: () => Navigator.maybePop(context),
          ),
          _buildFilterChips(),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _loadAndRescheduleReminders(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppEmptyState(
                        icon: Icons.error_outline,
                        title: 'Couldn\'t load reminders',
                        subtitle: 'Pull down to try again.\n${snapshot.error}',
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: AppEmptyState(
                        icon: Icons.alarm_outlined,
                        title: 'No reminders yet',
                        subtitle:
                            'Create your first reminder using the buttons below.',
                      ),
                    ),
                  );
                }

                // Parse + sort + filter
                final now = DateTime.now();
                final startOfTomorrow = DateTime(
                  now.year,
                  now.month,
                  now.day + 1,
                );
                final enriched =
                    snapshot.data!
                        .whereType<Map>()
                        .map((m) => Map<String, dynamic>.from(m))
                        .map((data) {
                          final dt = fyp_date.DateUtils.parseToLocal(
                            (data['datetime'] ?? '').toString(),
                          );
                          final completed =
                              (data['status'] ?? '').toString().toLowerCase() ==
                              'completed';
                          final overdue = !completed && dt.isBefore(now);
                          final today =
                              !completed &&
                              !overdue &&
                              dt.isBefore(startOfTomorrow);
                          return {
                            ...data,
                            '_dt': dt,
                            '_completed': completed,
                            '_overdue': overdue,
                            '_today': today,
                          };
                        })
                        .toList()
                      ..sort(
                        (a, b) => (a['_dt'] as DateTime).compareTo(
                          b['_dt'] as DateTime,
                        ),
                      );

                final filtered = enriched.where((r) {
                  switch (_filter) {
                    case 'today':
                      return r['_today'] == true;
                    case 'overdue':
                      return r['_overdue'] == true;
                    case 'upcoming':
                      return r['_completed'] == false &&
                          (r['_dt'] as DateTime).isAfter(now);
                    case 'done':
                      return r['_completed'] == true;
                    default:
                      return true;
                  }
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppEmptyState(
                        icon: _filterIcon(_filter),
                        title: _emptyTitleFor(_filter),
                        subtitle: 'Try a different filter to see more.',
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final r = filtered[index];
                      return _ReminderTile(
                        title: (r['title'] ?? 'Untitled').toString(),
                        dt: r['_dt'] as DateTime,
                        completed: r['_completed'] == true,
                        overdue: r['_overdue'] == true,
                        today: r['_today'] == true,
                        priority: (r['priority'] ?? 'medium').toString(),
                        location: (r['location'] ?? '').toString(),
                        onToggle: () => _toggleReminder(
                          r['id'].toString(),
                          r,
                          !(r['_completed'] == true),
                        ),
                        onDelete: () => _deleteReminder(r['id'].toString(), r),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  // ── Filter chips row ───────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    const filters = [
      ('all', 'All', Icons.list_rounded),
      ('today', 'Today', Icons.today_rounded),
      ('overdue', 'Overdue', Icons.warning_amber_rounded),
      ('upcoming', 'Upcoming', Icons.schedule_rounded),
      ('done', 'Completed', Icons.check_circle_outline),
    ];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (id, label, icon) = filters[i];
          final active = _filter == id;
          return Material(
            color: active
                ? AppColors.primary
                : (isDark ? AppColors.surfaceDarkElevated : Colors.white),
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () => setState(() => _filter = id),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: active ? Colors.white : AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : (isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary),
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Bottom action bar — Voice + Manual ─────────────────────────────────────
  Widget _buildBottomActionBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddReminderVoice(),
                    ),
                  );
                  if (result == true) setState(() {});
                },
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Voice'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddReminderManual(),
                    ),
                  );
                  if (result == true) setState(() {});
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Manual'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _filterIcon(String f) {
    switch (f) {
      case 'today':
        return Icons.today_rounded;
      case 'overdue':
        return Icons.warning_amber_rounded;
      case 'upcoming':
        return Icons.schedule_rounded;
      case 'done':
        return Icons.check_circle_outline;
      default:
        return Icons.alarm_outlined;
    }
  }

  String _emptyTitleFor(String f) {
    switch (f) {
      case 'today':
        return 'Nothing due today';
      case 'overdue':
        return 'You\'re all caught up';
      case 'upcoming':
        return 'No upcoming reminders';
      case 'done':
        return 'No completed reminders yet';
      default:
        return 'No reminders';
    }
  }

  // ── Backend actions ────────────────────────────────────────────────────────
  Future<void> _toggleReminder(
    String docId,
    Map<String, dynamic> data,
    bool completed,
  ) async {
    try {
      await FastApiService().put('/api/reminders/$docId', {
        'status': completed ? 'completed' : 'pending',
      });

      setState(() {});

      if (completed) {
        final dt = data['_dt'] as DateTime?;
        if (dt != null) {
          final id = _notificationIdFromDateTime(dt);
          await AlarmService.cancel(id);
        }
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(
          context,
          'Error updating reminder: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _deleteReminder(String docId, Map<String, dynamic> data) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: const Text('Are you sure you want to delete this reminder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FastApiService().delete('/api/reminders/$docId');

        final dt = data['_dt'] as DateTime?;
        if (dt != null) {
          final id = _notificationIdFromDateTime(dt);
          await AlarmService.cancel(id);
        }

        if (mounted) {
          UIFeedback.showSnackBar(context, 'Reminder deleted');
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          UIFeedback.showSnackBar(
            context,
            'Error deleting reminder: $e',
            isError: true,
          );
        }
      }
    }
  }
}

/// Single reminder list item — icon by inferred type, time, status pill,
/// optional location chip, completed strike-through.
class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.title,
    required this.dt,
    required this.completed,
    required this.overdue,
    required this.today,
    required this.priority,
    required this.location,
    required this.onToggle,
    required this.onDelete,
  });

  final String title;
  final DateTime dt;
  final bool completed;
  final bool overdue;
  final bool today;
  final String priority;
  final String location;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  IconData _pickIcon() {
    final t = title.toLowerCase();
    if (t.contains('flight') || t.contains('plane') || t.contains('fly')) {
      return Icons.flight_takeoff_rounded;
    }
    if (t.contains('hotel') ||
        t.contains('check-in') ||
        t.contains('checkin') ||
        t.contains('check in')) {
      return Icons.apartment_rounded;
    }
    if (t.contains('food') ||
        t.contains('lunch') ||
        t.contains('dinner') ||
        t.contains('breakfast') ||
        t.contains('eat')) {
      return Icons.restaurant_rounded;
    }
    if (t.contains('train') || t.contains('rail')) {
      return Icons.train_rounded;
    }
    if (t.contains('bus')) return Icons.directions_bus_rounded;
    if (t.contains('taxi') ||
        t.contains('car') ||
        t.contains('drive') ||
        t.contains('uber')) {
      return Icons.local_taxi_rounded;
    }
    if (t.contains('meet') || t.contains('call') || t.contains('appointment')) {
      return Icons.event_rounded;
    }
    if (t.contains('shop') || t.contains('buy') || t.contains('purchase')) {
      return Icons.shopping_bag_rounded;
    }
    return Icons.alarm_rounded;
  }

  Color _accent() {
    if (completed) return AppColors.success;
    if (overdue) return AppColors.danger;
    if (today) return AppColors.warning;
    return AppColors.infoBlue;
  }

  String _statusLabel() {
    if (completed) return 'Completed';
    if (overdue) return 'Overdue';
    if (today) return 'Today';
    return 'Upcoming';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon disc
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(_pickIcon(), color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: AppColors.textTertiary.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 13,
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              fyp_date.DateUtils.formatForReminders(dt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (location.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _pill(_statusLabel(), accent),
                          if (priority == 'high' && !completed)
                            _pill('High priority', AppColors.danger),
                        ],
                      ),
                    ],
                  ),
                ),
                // Trailing: complete checkbox + delete
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onToggle,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: completed
                              ? AppColors.success
                              : Colors.transparent,
                          border: Border.all(
                            color: completed
                                ? AppColors.success
                                : (isDark
                                      ? AppColors.borderDark
                                      : AppColors.borderLight),
                            width: 1.6,
                          ),
                        ),
                        child: completed
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
        ),
      ),
    );
  }
}
