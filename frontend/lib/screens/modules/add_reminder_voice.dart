import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../services/alarm_permission_helper.dart';
import '../../services/alarm_service.dart';
import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart' as fyp_date;
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';

/// Voice reminder creation — record audio, backend transcribes + extracts
/// time, user reviews and saves. All backend / scheduling logic preserved.
class AddReminderVoice extends StatefulWidget {
  const AddReminderVoice({super.key});

  @override
  State<AddReminderVoice> createState() => _AddReminderVoiceState();
}

class _AddReminderVoiceState extends State<AddReminderVoice>
    with TickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isSaving = false;
  String? _recordedText;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    // Check alarm permissions as soon as the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AlarmPermissionHelper.ensurePermissions(context);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  /// Client-side time parser — mirrors the backend's parse_time_from_text.
  /// Used as a safety net when the backend returns no scheduled_time.
  /// Handles: "at 4pm", "at 16:30", "today at 9am", "tomorrow at 8am", "4pm".
  DateTime? _parseTimeFromText(String text) {
    final t = text.toLowerCase();
    final now = DateTime.now();

    int? applyMeridiem(int hour, String mer) {
      final m = mer.replaceAll('.', '').trim();
      if (m == 'pm' && hour < 12) return hour + 12;
      if (m == 'am' && hour == 12) return 0;
      if (m.isEmpty && (hour < 0 || hour > 23)) return null;
      return hour;
    }

    // 1. "today at 4pm" / "tomorrow at 9am" / "at 4pm today" etc.
    final dayMatch = RegExp(r'\b(today|tomorrow)\b').firstMatch(t);
    final timeMatch = RegExp(
      r'\bat\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\b',
      caseSensitive: false,
    ).firstMatch(t);

    if (dayMatch != null && timeMatch != null) {
      int hour = int.tryParse(timeMatch.group(1) ?? '') ?? -1;
      if (hour < 0) return null;
      final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final adjusted = applyMeridiem(hour, (timeMatch.group(3) ?? '').toLowerCase());
      if (adjusted == null || minute < 0 || minute > 59) return null;
      final base = dayMatch.group(1) == 'tomorrow'
          ? now.add(const Duration(days: 1))
          : now;
      return DateTime(base.year, base.month, base.day, adjusted, minute);
    }

    // 2. "at 4pm" / "at 16:30" — no day word
    if (timeMatch != null) {
      int hour = int.tryParse(timeMatch.group(1) ?? '') ?? -1;
      if (hour < 0) return null;
      final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final adjusted = applyMeridiem(hour, (timeMatch.group(3) ?? '').toLowerCase());
      if (adjusted == null || minute < 0 || minute > 59) return null;
      var candidate = DateTime(now.year, now.month, now.day, adjusted, minute);
      if (candidate.isBefore(now)) candidate = candidate.add(const Duration(days: 1));
      return candidate;
    }

    // 3. Bare "4pm" / "4:30am"
    final bareTime = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false,
    ).firstMatch(t);
    if (bareTime != null) {
      int hour = int.tryParse(bareTime.group(1) ?? '') ?? -1;
      if (hour < 0) return null;
      final minute = int.tryParse(bareTime.group(2) ?? '0') ?? 0;
      final adjusted = applyMeridiem(hour, (bareTime.group(3) ?? '').toLowerCase());
      if (adjusted == null || minute < 0 || minute > 59) return null;
      var candidate = DateTime(now.year, now.month, now.day, adjusted, minute);
      if (candidate.isBefore(now)) candidate = candidate.add(const Duration(days: 1));
      return candidate;
    }

    return null;
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        UIFeedback.showSnackBar(
          context,
          'Microphone permission is required',
          isError: true,
        );
      }
      return;
    }
    try {
      final directory = await getApplicationDocumentsDirectory();
      final remindersDir = Directory('${directory.path}/reminders');
      if (!await remindersDir.exists()) {
        await remindersDir.create(recursive: true);
      }
      final path =
          '${remindersDir.path}/reminder_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(
          context,
          'Error starting recording: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path == null || !mounted) return;

      setState(() {
        _isTranscribing = true;
        _recordedText = null;
      });
      UIFeedback.showSnackBar(context, 'Transcribing your reminder…');

      try {
        // Build ISO-8601 string with local timezone offset so the backend
        // can tell GPT what "now" is in the user's timezone.
        final now = DateTime.now();
        final off = now.timeZoneOffset;
        final sign = off.isNegative ? '-' : '+';
        final hh = off.inHours.abs().toString().padLeft(2, '0');
        final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
        final userLocalTime =
            '${now.toIso8601String().split('.').first}$sign$hh:$mm';

        final result = await FastApiService().postVoice(
          '/api/reminders/voice',
          File(path),
          fields: {'user_local_time': userLocalTime},
        );
        if (!mounted) return;
        final hasDateTime =
            result['scheduled_time'] != null &&
            result['scheduled_time'] != 'null';
        final confidence = (result['confidence'] ?? 0.0).toDouble();

        setState(() {
          _recordedText =
              result['title'] ??
              result['transcript']?.split('\n').first ??
              'Voice reminder';

          if (hasDateTime) {
            // Backend successfully extracted date+time
            try {
              final dt = fyp_date.DateUtils.parseToLocal(
                result['scheduled_time']?.toString(),
              );
              _selectedDate = dt;
              _selectedTime = TimeOfDay.fromDateTime(dt);
            } catch (_) {}
          } else {
            // Backend found no time — try client-side parsing from transcript then title
            final rawTranscript = result['transcript']?.toString() ?? '';
            final textToParse = rawTranscript.isNotEmpty
                ? rawTranscript
                : (_recordedText ?? '');
            final fallback = textToParse.isNotEmpty
                ? _parseTimeFromText(textToParse)
                : null;
            if (fallback != null && fallback.isAfter(DateTime.now())) {
              _selectedDate = fallback;
              _selectedTime = TimeOfDay.fromDateTime(fallback);
            }
          }
          _isTranscribing = false;
        });

        // Auto-save when AI is confident (≥70 %) and timing is detected.
        if (confidence >= 0.7 &&
            _selectedDate != null &&
            _selectedTime != null) {
          UIFeedback.showSnackBar(
            context,
            '✨ AI detected time — scheduling automatically',
          );
          _saveReminder();
        } else if (_selectedDate != null && _selectedTime != null) {
          // Time was detected but confidence is low — let user confirm
          UIFeedback.showSnackBar(
            context,
            'Time detected. Review and tap Save.',
          );
        } else {
          // No time detected — prompt user to set it
          UIFeedback.showSnackBar(
            context,
            'Tap "Set date & time" then Save to schedule.',
          );
          _showDateTimePicker();
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _recordedText = 'Voice reminder (transcription failed)';
          _isTranscribing = false;
        });
        UIFeedback.showSnackBar(
          context,
          'Transcription failed: $e. You can still set it manually.',
          isError: true,
        );
        _showDateTimePicker();
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(
          context,
          'Error stopping recording: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _showDateTimePicker() async {
    // Don't open the date/time pickers while a save (and its screen pop) is in
    // flight — two simultaneous navigator actions throw a !_debugLocked crash.
    if (_isSaving) return;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (!mounted || pickedDate == null) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (!mounted || pickedTime == null) return;
    setState(() {
      _selectedDate = pickedDate;
      _selectedTime = pickedTime;
    });
  }

  Future<void> _saveReminder() async {
    // Re-entrancy guard: the auto-save (high-confidence path) and a manual Save
    // tap must never run at the same time, or they'll both try to pop the screen.
    if (_isSaving) return;
    if (_recordedText == null ||
        _selectedDate == null ||
        _selectedTime == null) {
      UIFeedback.showSnackBar(
        context,
        'Please record and set date/time',
        isError: true,
      );
      return;
    }
    final user = _auth.currentUser;
    if (user == null) {
      UIFeedback.showSnackBar(context, 'Please log in', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final tz.TZDateTime tzDt = tz.TZDateTime(
        tz.local,
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      if (tzDt.isBefore(tz.TZDateTime.now(tz.local))) {
        if (mounted) {
          UIFeedback.showSnackBar(
            context,
            'Please select a future date and time',
            isError: true,
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      await FastApiService().post('/api/reminders/', {
        'title': _recordedText!,
        'datetime': tzDt.toUtc().toIso8601String(),
        'user_id': user.uid,
        'status': 'pending',
        'priority': 'medium',
      });

      // Real alarm — rings even when the app is killed.
      final alarmId = tzDt.millisecondsSinceEpoch
          .remainder(2000000000)
          .toInt();
      try {
        await AlarmService.set(
          id: alarmId,
          title: 'Travel Reminder ⏰',
          body: _recordedText!,
          scheduledDate: tzDt.toLocal(),
        );
      } catch (e) {
        debugPrint('AddReminderVoice: alarm schedule failed: $e');
      }
      if (!mounted) return;
      final timeStr = DateFormat('MMM d, h:mm a').format(tzDt.toLocal());
      UIFeedback.showSnackBar(context, 'Alarm scheduled for $timeStr');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(
          context,
          'Error creating reminder: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasDateTime = _selectedDate != null && _selectedTime != null;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'Voice Reminder',
            subtitle: 'Speak it — Travel Buddy AI extracts the time',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Pulsing mic
                  GestureDetector(
                    onTap: _isRecording ? _stopRecording : _startRecording,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, _) {
                        final v = _isRecording ? _pulseController.value : 0.0;
                        return SizedBox(
                          width: 240,
                          height: 240,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_isRecording)
                                Container(
                                  width: 240,
                                  height: 240,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.danger.withValues(
                                      alpha: 0.18 * (1 - v),
                                    ),
                                  ),
                                ),
                              Container(
                                width: 200 - v * 14,
                                height: 200 - v * 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      (_isRecording
                                              ? AppColors.danger
                                              : AppColors.primary)
                                          .withValues(alpha: 0.14),
                                ),
                              ),
                              Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: _isRecording
                                        ? const [
                                            Color(0xFFFF7B95),
                                            AppColors.danger,
                                          ]
                                        : const [
                                            Color(0xFF7B5AFF),
                                            AppColors.primaryDark,
                                          ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (_isRecording
                                                  ? AppColors.danger
                                                  : AppColors.primary)
                                              .withValues(alpha: 0.42),
                                      blurRadius: 22,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isRecording
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isRecording
                        ? 'Listening… tap to stop'
                        : 'Tap to start recording',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (_isTranscribing) ...[
                    const SizedBox(height: 28),
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(
                      'AI is transcribing…',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (_recordedText != null && !_isTranscribing) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        boxShadow: isDark ? const [] : AppShadows.softCard,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.alarm,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Reminder',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: 0.4,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _recordedText!,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          if (hasDateTime) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 14,
                                  color: AppColors.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${DateFormat('EEE, d MMM').format(_selectedDate!)} • ${_selectedTime!.format(context)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 14),
                          if (!hasDateTime)
                            OutlinedButton.icon(
                              onPressed: _showDateTimePicker,
                              icon: const Icon(Icons.event_note_rounded),
                              label: const Text('Set date & time'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                            )
                          else
                            // Voice reminder with a detected time: just Save
                            // (with its spinner). No "Edit time" button — the
                            // reminder is created when the spinner completes.
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveReminder,
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.alarm_add_rounded),
                                label: Text(_isSaving ? 'Saving…' : 'Save'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_recordedText == null &&
                      !_isRecording &&
                      !_isTranscribing) ...[
                    const SizedBox(height: 28),
                    _hintRow(
                      isDark,
                      Icons.lightbulb_outline,
                      'Try: "Remind me to check in tomorrow at 9 AM"',
                    ),
                    const SizedBox(height: 10),
                    _hintRow(
                      isDark,
                      Icons.lightbulb_outline,
                      'Try: "Flight to Skardu next Monday at 6:30 AM"',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintRow(bool isDark, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tips_and_updates_outlined,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
