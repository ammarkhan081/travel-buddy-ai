import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'dart:io';
import '../../services/fastapi_service.dart';
import '../../utils/ui_utils.dart';
import '../../utils/date_utils.dart' as fyp_date;
import '../../services/notification_service.dart';

class AddReminderVoice extends StatefulWidget {
  const AddReminderVoice({super.key});

  @override
  State<AddReminderVoice> createState() => _AddReminderVoiceState();
}

class _AddReminderVoiceState extends State<AddReminderVoice> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isRecording = false;
  bool _isSaving = false;
  String? _recordedText;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Microphone permission is required', isError: true);
      }
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final remindersDir = Directory('${directory.path}/reminders');
      if (!await remindersDir.exists()) {
        await remindersDir.create(recursive: true);
      }
      
      final path = '${remindersDir.path}/reminder_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error starting recording: $e', isError: true);
      }
    }
  }

  bool _isTranscribing = false;

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path != null && mounted) {
        setState(() {
          _isTranscribing = true;
          _recordedText = null; // Clear previous if any
        });

        UIFeedback.showSnackBar(context, 'Transcribing your reminder...');

        final apiService = FastApiService();
        try {
          // POST audio to backend
          final result = await apiService.postVoice('/api/reminders/voice', File(path));
          
          if (mounted) {
            final bool hasDateTime = result['scheduled_time'] != null && result['scheduled_time'] != 'null';
            final double confidence = (result['confidence'] ?? 0.0).toDouble();

            setState(() {
              _recordedText = result['title'] ?? result['transcript']?.split('\n').first ?? 'Voice reminder';
              
              if (hasDateTime) {
                try {
                  final dt = fyp_date.DateUtils.parseToLocal(
                    result['scheduled_time']?.toString(),
                  );
                  _selectedDate = dt;
                  _selectedTime = TimeOfDay.fromDateTime(dt);
                } catch (_) {}
              }
              _isTranscribing = false;
            });

            // --- INTELLIGENT AUTO-SAVE FLOW ---
            if (confidence > 0.8 && _selectedDate != null && _selectedTime != null) {
              UIFeedback.showSnackBar(context, '*** AI Confidence High: Scheduling Auto-magically!');
              _saveReminder(); // Auto-trigger save
            } else {
              UIFeedback.showSnackBar(context, 'Transcription complete! Please review and save.');
              if (_selectedDate == null || _selectedTime == null) {
                _showDateTimePicker();
              }
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _recordedText = 'Voice reminder (Transcription failed)';
              _isTranscribing = false;
            });
            UIFeedback.showSnackBar(context, 'Transcription failed: $e. You can still set it manually.', isError: true);
            _showDateTimePicker();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error stopping recording: $e', isError: true);
      }
    }
  }

  Future<void> _showDateTimePicker() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted) return;

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (!mounted) return;

      if (pickedTime != null) {
        setState(() {
          _selectedDate = pickedDate;
          _selectedTime = pickedTime;
        });
      }
    }
  }

  Future<void> _saveReminder() async {
    if (_recordedText == null || _selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please record and set date/time')),
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

    setState(() {
      _isSaving = true;
    });

    try {
      final tz.TZDateTime tzReminderDateTime = tz.TZDateTime(
        tz.local,
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
        0,
      );

      final DateTime reminderDateTime = tzReminderDateTime.toLocal();

      // Validate future time
      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
      if (tzReminderDateTime.isBefore(now)) {
        if (mounted) {
          UIFeedback.showSnackBar(context, 'Please select a future date and time', isError: true);
        }
        setState(() => _isSaving = false);
        return;
      }

      final apiService = FastApiService();
      await apiService.post('/api/reminders/', {
        'title': _recordedText!,
        'datetime': tzReminderDateTime.toUtc().toIso8601String(),
        'user_id': user.uid,
        'status': 'pending',
        'priority': 'medium',
      });

      if (mounted) {
        final int notificationId =
            tzReminderDateTime.millisecondsSinceEpoch.remainder(2147483647).toInt();

        try {
          await NotificationService().scheduleNotificationTZ(
            id: notificationId,
            title: 'Travel Reminder',
            body: _recordedText!,
            scheduledTZDate: tzReminderDateTime,
          );
        } catch (e) {
          debugPrint('AddReminderVoice: Error scheduling notification: $e');
        }

        if (!mounted) return;
        final timeStr = DateFormat('MMM d, h:mm a').format(reminderDateTime);
        UIFeedback.showSnackBar(context, 'Alarm scheduled for $timeStr');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error creating reminder: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Reminder (Voice)'),
        backgroundColor: const Color(0xFF6200EE),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Record Your Reminder',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 48),
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: _isRecording
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.purple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                iconSize: 80,
                icon: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: _isRecording ? Colors.red : Colors.purple,
                ),
                onPressed: _isRecording ? _stopRecording : _startRecording,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              _isRecording ? 'Recording... Tap to stop' : 'Tap to start recording',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            if (_isTranscribing) ...[
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('AI is transcribing...'),
            ],
            if (_recordedText != null && !_isTranscribing) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      'Recorded: $_recordedText',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (_selectedDate != null && _selectedTime != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Date: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                      ),
                      Text('Time: ${_selectedTime!.format(context)}'),
                    ],
                  ],
                ),
              ),
            ],
            if (_recordedText != null && (_selectedDate == null || _selectedTime == null)) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _showDateTimePicker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('Set Date & Time'),
              ),
            ],
            if (_recordedText != null && _selectedDate != null && _selectedTime != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveReminder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6200EE),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Save Reminder'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
