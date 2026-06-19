import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:timezone/timezone.dart' as tz;

import '../../services/fastapi_service.dart';
import '../../services/alarm_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class RecordVoiceNoteScreen extends StatefulWidget {
  const RecordVoiceNoteScreen({super.key});

  @override
  State<RecordVoiceNoteScreen> createState() => _RecordVoiceNoteScreenState();
}

class _RecordVoiceNoteScreenState extends State<RecordVoiceNoteScreen> {
  bool _isRecording = false;
  Duration _duration = Duration.zero;
  final AudioRecorder _audioRecorder = AudioRecorder();
  Timer? _timer;
  bool _isUploading = false;

  Future<void> _saveTranscriptForHistory(String transcript) async {
    final text = transcript.trim();
    if (text.isEmpty) return;
    await FastApiService().post('/api/voice-notes/from-text', {
      'transcript': text,
    });
  }

  int? _extractReviewId(Map<dynamic, dynamic> result) {
    final raw = result['review_id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '');
  }

  Future<void> _resolveDecisionReview(
    int? reviewId,
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    if (reviewId == null) return;
    await FastApiService().post('/api/intent/reviews/$reviewId/resolve', {
      'action': action,
      'resolution_payload': payload ?? {},
    });
  }

  DateTime? _parseSuggestedDateTime(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty || raw == 'null') return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// Parses a datetime from the transcript text.
  /// Handles: "today at 4pm", "tomorrow at 9am", "at 4pm" (no day → today/tomorrow),
  /// "4pm", "4:30 am" (bare time with am/pm marker).
  DateTime? _parseDateTimeFromTranscript(String transcript) {
    final text = transcript.toLowerCase();
    final now = DateTime.now();

    // Helper: normalise hour with am/pm
    int? _applyMeridiem(int hour, String mer) {
      final m = mer.replaceAll('.', '').trim();
      if (m == 'pm' && hour < 12) return hour + 12;
      if (m == 'am' && hour == 12) return 0;
      if (m.isEmpty && (hour < 0 || hour > 23)) return null;
      return hour;
    }

    // 1. "today at 4pm" / "tomorrow at 9am" / "at 4pm today" / "at 4pm tomorrow"
    final dayMatch = RegExp(r'\b(today|tomorrow)\b').firstMatch(text);
    final timeMatch = RegExp(
      r'\bat\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\b',
      caseSensitive: false,
    ).firstMatch(text);

    if (dayMatch != null && timeMatch != null) {
      int hour = int.tryParse(timeMatch.group(1) ?? '') ?? -1;
      if (hour < 0) return null;
      final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final mer = (timeMatch.group(3) ?? '').toLowerCase();
      final adjusted = _applyMeridiem(hour, mer);
      if (adjusted == null || minute < 0 || minute > 59) return null;
      hour = adjusted;
      final dayWord = dayMatch.group(1)!;
      final base = dayWord == 'tomorrow'
          ? now.add(const Duration(days: 1))
          : now;
      return DateTime(base.year, base.month, base.day, hour, minute);
    }

    // 2. "at 4pm" / "at 16:30" — no day word → default to today, tomorrow if past
    if (timeMatch != null) {
      int hour = int.tryParse(timeMatch.group(1) ?? '') ?? -1;
      if (hour < 0) return null;
      final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
      final mer = (timeMatch.group(3) ?? '').toLowerCase();
      final adjusted = _applyMeridiem(hour, mer);
      if (adjusted == null || minute < 0 || minute > 59) return null;
      hour = adjusted;
      var candidate = DateTime(now.year, now.month, now.day, hour, minute);
      if (candidate.isBefore(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    // 3. Bare "4pm" / "4:30am" — last resort (requires explicit am/pm)
    final bareTime = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (bareTime != null) {
      int hour = int.tryParse(bareTime.group(1) ?? '') ?? -1;
      if (hour < 0) return null;
      final minute = int.tryParse(bareTime.group(2) ?? '0') ?? 0;
      final mer = (bareTime.group(3) ?? '').toLowerCase();
      final adjusted = _applyMeridiem(hour, mer);
      if (adjusted == null || minute < 0 || minute > 59) return null;
      hour = adjusted;
      var candidate = DateTime(now.year, now.month, now.day, hour, minute);
      if (candidate.isBefore(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    }

    return null;
  }

  DateTime? _resolveReminderDateTime(String transcript, DateTime? suggested) {
    final now = DateTime.now();

    // Prefer backend-provided suggestion when valid and future.
    if (suggested != null && suggested.isAfter(now)) {
      return suggested;
    }

    // Fallback to transcript parsing for ASR-like phrases.
    final parsed = _parseDateTimeFromTranscript(transcript);
    if (parsed != null && parsed.isAfter(now)) {
      return parsed;
    }

    return null;
  }

  Future<DateTime?> _pickDateTime({DateTime? initial}) async {
    final now = DateTime.now();
    final seed = initial ?? now.add(const Duration(minutes: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (pickedDate == null || !mounted) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(seed),
    );
    if (pickedTime == null) return null;

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  Future<void> _createReminder({
    required String title,
    required DateTime when,
  }) async {
    await FastApiService().post('/api/reminders/', {
      'title': title,
      'datetime': when.toUtc().toIso8601String(),
      'status': 'pending',
      'priority': 'medium',
    });
    // Schedule a real alarm so a reminder created here actually rings — parity
    // with the manual and voice reminder screens. Same ID derivation as
    // RemindersModule so it can be cancelled correctly. Best-effort.
    try {
      final tzDt = tz.TZDateTime.from(when, tz.local);
      final alarmId =
          tzDt.millisecondsSinceEpoch.remainder(2000000000).toInt();
      await AlarmService.set(
        id: alarmId,
        title: 'Travel Reminder ⏰',
        body: title,
        scheduledDate: when,
      );
    } catch (e) {
      debugPrint('RecordVoiceNote: alarm schedule failed: $e');
    }
  }

  Future<void> _createExpense({
    required String transcript,
    required double amount,
    required String category,
  }) async {
    await FastApiService().post('/api/expenses/', {
      'amount': amount,
      'category': category,
      'description': transcript,
      'date': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<String> _handleReminderAction(Map<dynamic, dynamic> result, String transcript) async {
    final reviewId = _extractReviewId(result);
    final details = (result['details'] is Map) ? result['details'] as Map : const {};
    String title = (details['title']?.toString().trim().isNotEmpty == true)
        ? details['title'].toString().trim()
        : transcript;
    DateTime? dateTime = _parseSuggestedDateTime(details['datetime']);

    if (!mounted) return 'rejected';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reminder Detected'),
        content: Text(
          dateTime != null
              ? 'Create reminder for ${DateFormat('MMM d, yyyy • h:mm a').format(dateTime)}?'
              : 'No valid time detected. You can edit before creating.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reject'), child: const Text('Reject')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'edit'), child: const Text('Edit')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'accept'), child: const Text('Accept')),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'reject') {
      await _resolveDecisionReview(reviewId, 'rejected');
      return 'rejected';
    }

    if (choice == 'edit') {
      final controller = TextEditingController(text: title);
      final editedTitle = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit Reminder Title'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Next')),
          ],
        ),
      );
      if (editedTitle == null || editedTitle.isEmpty || !mounted) {
        await _resolveDecisionReview(reviewId, 'rejected');
        return 'rejected';
      }
      title = editedTitle;
      dateTime = await _pickDateTime(initial: dateTime);
      if (dateTime == null || !mounted) {
        await _resolveDecisionReview(reviewId, 'rejected');
        return 'rejected';
      }
      await _createReminder(title: title, when: dateTime);
      await _resolveDecisionReview(
        reviewId,
        'edited',
        payload: {
          'title': title,
          'datetime': dateTime.toUtc().toIso8601String(),
        },
      );
      return 'created';
    }

    // Accept must be direct create with detected values only.
    dateTime = _resolveReminderDateTime(transcript, dateTime);
    if (kDebugMode) {
      debugPrint('Reminder Accept: parsed datetime=$dateTime transcript="$transcript"');
    }
    if (dateTime == null || !dateTime.isAfter(DateTime.now())) {
      return 'accept_failed_missing_or_past_time';
    }
    await _createReminder(title: title, when: dateTime);
    await _resolveDecisionReview(
      reviewId,
      'accepted',
      payload: {
        'title': title,
        'datetime': dateTime.toUtc().toIso8601String(),
      },
    );
    return 'created';
  }

  Future<String> _handleExpenseAction(Map<dynamic, dynamic> result, String transcript) async {
    final reviewId = _extractReviewId(result);
    final details = (result['details'] is Map) ? result['details'] as Map : const {};
    double amount = double.tryParse((details['amount'] ?? '').toString()) ?? 0.0;
    String category = (details['category']?.toString().trim().isNotEmpty == true)
        ? details['category'].toString().trim()
        : 'other';

    if (!mounted) return 'rejected';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Expense Detected'),
        content: Text(amount > 0 ? 'Create expense for ${amount.toStringAsFixed(2)}?' : 'Amount needs review before creating.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reject'), child: const Text('Reject')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'edit'), child: const Text('Edit')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'accept'), child: const Text('Accept')),
        ],
      ),
    );

    if (!mounted || choice == null || choice == 'reject') {
      await _resolveDecisionReview(reviewId, 'rejected');
      return 'rejected';
    }

    if (choice == 'edit') {
      final amountController = TextEditingController(text: amount > 0 ? amount.toString() : '');
      final categoryController = TextEditingController(text: category);
      final edited = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit Expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
              ),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      );
      if (edited != true || !mounted) {
        await _resolveDecisionReview(reviewId, 'rejected');
        return 'rejected';
      }
      amount = double.tryParse(amountController.text.trim()) ?? 0.0;
      category = categoryController.text.trim().isEmpty ? 'other' : categoryController.text.trim();
      if (amount <= 0) {
        return 'edit_failed_invalid_amount';
      }

      await _createExpense(transcript: transcript, amount: amount, category: category);
      await _resolveDecisionReview(
        reviewId,
        'edited',
        payload: {
          'amount': amount,
          'category': category,
          'description': transcript,
        },
      );
      return 'created';
    }

    // Accept must be direct create with detected values only.
    if (amount <= 0) {
      return 'accept_failed_missing_amount';
    }
    await _createExpense(transcript: transcript, amount: amount, category: category);
    await _resolveDecisionReview(
      reviewId,
      'accepted',
      payload: {
        'amount': amount,
        'category': category,
        'description': transcript,
      },
    );
    return 'created';
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
            title: 'Record Voice Note',
            subtitle: 'Speak naturally — Travel Buddy AI figures it out',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  children: [
                    // Waveform card
                    Container(
                      width: double.infinity,
                      height: 160,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        boxShadow:
                            isDark ? const [] : AppShadows.softCard,
                      ),
                      child: CustomPaint(
                        painter: WaveformPainter(_isRecording, isDark),
                        child: Center(
                          child: Text(
                            _isRecording
                                ? 'Recording…'
                                : 'Tap the mic to start',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Duration display
                    Text(
                      _formatDuration(_duration),
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 1.5,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Mic button
                    GestureDetector(
                      onTap: _isUploading
                          ? null
                          : (_isRecording
                              ? _stopRecording
                              : _startRecording),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 130,
                        height: 130,
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
                              color: (_isRecording
                                      ? AppColors.danger
                                      : AppColors.primary)
                                  .withValues(alpha: 0.40),
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
                          size: 56,
                        ),
                      ),
                    ),
                    if (_isUploading) ...[
                      const SizedBox(height: 22),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      Text(
                        'Uploading and processing…',
                        style: TextStyle(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required to record voice notes'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final voiceNotesDir = Directory('${directory.path}/voice_notes');
      if (!await voiceNotesDir.exists()) {
        await voiceNotesDir.create(recursive: true);
      }
      
      final path = '${voiceNotesDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      
      await _audioRecorder.start(
        const RecordConfig(),
        path: path,
      );
      
      setState(() {
        _isRecording = true;
        _duration = Duration.zero;
      });
      
      // Start timer to update duration
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted && _isRecording) {
          setState(() {
            _duration = Duration(seconds: _duration.inSeconds + 1);
          });
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Recording started. Saving to: ${voiceNotesDir.path}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      _timer?.cancel();
      
      setState(() {
        _isRecording = false;
      });
      
      if (mounted && path != null) {
        final file = File(path);
        final fileSize = await file.length();
        final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

        setState(() {
          _isUploading = true;
        });

        try {
          final result = await FastApiService().postVoice('/api/intent/process-voice?persist=false', file);
          final transcript = (result is Map && result['transcript'] != null)
              ? result['transcript'].toString()
              : '';
          final intent = (result is Map && result['intent'] != null)
              ? result['intent'].toString()
              : 'other';
          final action = (result is Map && result['action'] != null)
              ? result['action'].toString()
              : '';
          final requiresReview = (result is Map && result['requires_review'] == true);

          await _saveTranscriptForHistory(transcript);

          String decisionOutcome = 'saved';
          if (intent == 'reminder') {
            decisionOutcome = await _handleReminderAction(result as Map<dynamic, dynamic>, transcript);
          } else if (intent == 'expense') {
            decisionOutcome = await _handleExpenseAction(result as Map<dynamic, dynamic>, transcript);
          }

          String statusLine = 'Voice processed successfully';
          if (intent == 'reminder') {
            if (decisionOutcome == 'created') {
              statusLine = 'Reminder created successfully.';
            } else if (decisionOutcome == 'rejected') {
              statusLine = 'Reminder rejected. No reminder created.';
            } else {
              statusLine = 'Reminder not created on accept: missing valid future time. Use Edit.';
            }
          } else if (intent == 'expense') {
            if (decisionOutcome == 'created') {
              statusLine = 'Expense created successfully.';
            } else if (decisionOutcome == 'rejected') {
              statusLine = 'Expense rejected. No expense created.';
            } else {
              statusLine = 'Expense not created on accept: missing valid amount. Use Edit.';
            }
          } else if (action == 'stored_as_knowledge') {
            statusLine = 'Voice note transcribed and saved';
          } else if (requiresReview) {
            statusLine = 'Intent detected but needs manual review';
          }

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusLine),
                  if (transcript.isNotEmpty)
                    Text(
                      transcript.length > 60 ? '${transcript.substring(0, 60)}...' : transcript,
                      style: const TextStyle(fontSize: 12),
                    ),
                  Text('Size: $fileSizeKB KB', style: const TextStyle(fontSize: 12)),
                ],
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.pop(context, true); // Refresh voice notes list
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Transcription failed: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        } finally {
          if (mounted) {
            setState(() {
              _isUploading = false;
            });
          }
        }
      }
    } catch (e) {
      _timer?.cancel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class WaveformPainter extends CustomPainter {
  final bool isRecording;
  final bool isDark;

  WaveformPainter(this.isRecording, this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    final activeColor = isRecording ? AppColors.primary : AppColors.primary.withValues(alpha: 0.18);
    final paint = Paint()
      ..color = activeColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw stylised waveform bars
    const bars = 28;
    for (int i = 0; i < bars; i++) {
      final x = (size.width / bars) * i + (size.width / bars / 2);
      // Wave-like heights — taller in the middle when recording
      final mid = bars / 2;
      final distFromCenter = (i - mid).abs() / mid;
      final base = isRecording ? (1 - distFromCenter) : 0.20;
      final variation = (i % 3 == 0)
          ? 0.55
          : (i % 3 == 1)
              ? 0.30
              : 0.45;
      final height = (size.height / 2) * (0.20 + base * variation + 0.08);
      canvas.drawLine(
        Offset(x, size.height / 2 - height),
        Offset(x, size.height / 2 + height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.isRecording != isRecording || oldDelegate.isDark != isDark;
}
