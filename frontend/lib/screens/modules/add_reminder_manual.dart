import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../services/notification_service.dart';
import '../../services/fastapi_service.dart';

class AddReminderManual extends StatefulWidget {
  const AddReminderManual({super.key});

  @override
  State<AddReminderManual> createState() => _AddReminderManualState();
}

class _AddReminderManualState extends State<AddReminderManual> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _saveReminder() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both date and time')),
      );
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to create reminders')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // KEY FIX: Build TZDateTime directly in the local timezone.
      // Do NOT use plain DateTime() + tz.TZDateTime.from() — that conversion
      // causes a timezone mismatch on some devices (especially Tecno HiOS)
      // where the alarm appears to be in the past and fires immediately.
      final tz.TZDateTime tzScheduled = tz.TZDateTime(
        tz.local,
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
        0, // seconds
      );

      debugPrint('AddReminderManual: Now (TZ):       ${tz.TZDateTime.now(tz.local)}');
      debugPrint('AddReminderManual: Scheduled (TZ): $tzScheduled');

      // Validate it's in the future before doing anything
      if (tzScheduled.isBefore(tz.TZDateTime.now(tz.local))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a future date and time'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      final DateTime reminderDateTime = tzScheduled.toLocal();

      final apiService = FastApiService();
      await apiService.post('/api/reminders/', {
        'title': _titleController.text.trim(),
        'datetime': tzScheduled.toUtc().toIso8601String(),
        'user_id': user.uid,
        'status': 'pending',
        'priority': 'medium',
      });

      if (mounted) {
        // Safe notification ID
        final int notificationId =
            tzScheduled.millisecondsSinceEpoch.remainder(2000000000).toInt();

        debugPrint('AddReminderManual: Notification ID: $notificationId');

        try {
          await NotificationService().scheduleNotificationTZ(
            id: notificationId,
            title: 'Travel Reminder',
            body: _titleController.text.trim(),
            scheduledTZDate: tzScheduled,
          );
        } catch (e) {
          debugPrint('AddReminderManual: Error scheduling notification: $e');
        }

        if (!mounted) return;
        final String timeStr = DateFormat('MMM d, h:mm a').format(reminderDateTime);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarm set for $timeStr'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating reminder: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Reminder'),
        backgroundColor: const Color(0xFF6200EE),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Reminder Title',
                  prefixIcon: Icon(Icons.title),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Date'),
                subtitle: Text(
                  _selectedDate == null
                      ? 'Select date'
                      : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectDate,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('Time'),
                subtitle: Text(
                  _selectedTime == null
                      ? 'Select time'
                      : _selectedTime!.format(context),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectTime,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveReminder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6200EE),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Create Reminder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
