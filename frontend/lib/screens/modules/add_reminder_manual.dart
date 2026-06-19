import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../services/alarm_permission_helper.dart';
import '../../services/alarm_service.dart';
import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

/// Manual reminder creation — title, date, time, priority, optional location.
/// All backend + notification logic is preserved exactly.
class AddReminderManual extends StatefulWidget {
  const AddReminderManual({super.key});

  @override
  State<AddReminderManual> createState() => _AddReminderManualState();
}

class _AddReminderManualState extends State<AddReminderManual> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _priority = 'medium';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Check alarm permissions as soon as the screen opens so the user can
    // grant SCHEDULE_EXACT_ALARM and battery-optimisation exemption before
    // trying to save a reminder.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AlarmPermissionHelper.ensurePermissions(context);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _saveReminder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null || _selectedTime == null) {
      _snack('Please select both date and time', AppColors.warning);
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      _snack('Please log in to create reminders', AppColors.danger);
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Build TZDateTime directly in local zone to avoid HiOS / Tecno bugs
      // where DateTime → tz conversion drops timezone info.
      final tz.TZDateTime tzScheduled = tz.TZDateTime(
        tz.local,
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
      debugPrint('AddReminderManual: Now (TZ):       ${tz.TZDateTime.now(tz.local)}');
      debugPrint('AddReminderManual: Scheduled (TZ): $tzScheduled');
      if (tzScheduled.isBefore(tz.TZDateTime.now(tz.local))) {
        _snack('Please select a future date and time', AppColors.warning);
        setState(() => _isSaving = false);
        return;
      }

      final reminderDateTime = tzScheduled.toLocal();
      final location = _locationController.text.trim();

      await FastApiService().post('/api/reminders/', {
        'title': _titleController.text.trim(),
        'datetime': tzScheduled.toUtc().toIso8601String(),
        'user_id': user.uid,
        'status': 'pending',
        'priority': _priority,
        if (location.isNotEmpty) 'location': location,
      });

      // Schedule a real alarm — rings even when the app is killed.
      // Uses the same ID derivation as RemindersModule.cancel() so it can
      // be cancelled correctly when the reminder is marked done or deleted.
      final alarmId = tzScheduled.millisecondsSinceEpoch
          .remainder(2000000000)
          .toInt();
      try {
        await AlarmService.set(
          id: alarmId,
          title: 'Travel Reminder ⏰',
          body: _titleController.text.trim(),
          scheduledDate: tzScheduled.toLocal(),
        );
      } catch (e) {
        debugPrint('AddReminderManual: alarm schedule failed: $e');
      }

      if (!mounted) return;
      final timeStr = DateFormat('MMM d, h:mm a').format(reminderDateTime);
      _snack('Alarm set for $timeStr', AppColors.success);
      Navigator.pop(context, true);
    } catch (e) {
      _snack('Error creating reminder: $e', AppColors.danger);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
            title: 'New Reminder',
            subtitle: 'Schedule an alert for your trip',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card(
                      isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionLabel('Reminder', isDark),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              hintText: 'e.g. Flight to Islamabad',
                              prefixIcon: const Icon(
                                  Icons.title_rounded,
                                  color: AppColors.primary),
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.surfaceDarkElevated
                                  : AppColors.bgLight,
                            ),
                            textCapitalization:
                                TextCapitalization.sentences,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please enter a title';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _locationController,
                            decoration: InputDecoration(
                              hintText: 'Location (optional)',
                              prefixIcon: const Icon(
                                  Icons.location_on_outlined,
                                  color: AppColors.primary),
                              filled: true,
                              fillColor: isDark
                                  ? AppColors.surfaceDarkElevated
                                  : AppColors.bgLight,
                            ),
                            textCapitalization:
                                TextCapitalization.words,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _card(
                      isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionLabel('When', isDark),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _pickerTile(
                                  icon: Icons.calendar_today_rounded,
                                  label: 'Date',
                                  value: _selectedDate == null
                                      ? 'Select date'
                                      : DateFormat('EEE, d MMM')
                                          .format(_selectedDate!),
                                  onTap: _selectDate,
                                  isDark: isDark,
                                  isPlaceholder: _selectedDate == null,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _pickerTile(
                                  icon: Icons.schedule_rounded,
                                  label: 'Time',
                                  value: _selectedTime == null
                                      ? 'Select time'
                                      : _selectedTime!.format(context),
                                  onTap: _selectTime,
                                  isDark: isDark,
                                  isPlaceholder: _selectedTime == null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _card(
                      isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionLabel('Priority', isDark),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _priorityChip('low', 'Low',
                                  AppColors.success, isDark),
                              const SizedBox(width: 8),
                              _priorityChip('medium', 'Medium',
                                  AppColors.infoBlue, isDark),
                              const SizedBox(width: 8),
                              _priorityChip('high', 'High',
                                  AppColors.danger, isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveReminder,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : const Icon(Icons.alarm_add_rounded),
                      label: Text(_isSaving ? 'Creating…' : 'Create Reminder'),
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(bool isDark, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: isDark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondary,
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    required bool isDark,
    required bool isPlaceholder,
  }) {
    return Material(
      color: isDark
          ? AppColors.surfaceDarkElevated
          : AppColors.bgLight,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isPlaceholder
                      ? (isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary)
                      : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityChip(
      String value, String label, Color color, bool isDark) {
    final active = _priority == value;
    return Expanded(
      child: Material(
        color: active
            ? color.withValues(alpha: isDark ? 0.22 : 0.14)
            : (isDark
                ? AppColors.surfaceDarkElevated
                : AppColors.bgLight),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () => setState(() => _priority = value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: active ? color : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: active
                      ? color
                      : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
