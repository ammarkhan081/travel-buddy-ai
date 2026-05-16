import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import '../../services/fastapi_service.dart';

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

  DateTime? _parseDateTimeFromTranscript(String transcript) {
    final text = transcript.toLowerCase();
    final dayMatch = RegExp(r'\b(today|tomorrow)\b').firstMatch(text);
    // Accept common variations: "5pm", "5 pm", "5 p.m.", "17:30"
    final timeMatch = RegExp(
      r'\bat\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (dayMatch == null || timeMatch == null) return null;

    final dayWord = dayMatch.group(1)!;
    int hour = int.tryParse(timeMatch.group(1) ?? '') ?? -1;
    final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
    var mer = (timeMatch.group(3) ?? '').toLowerCase();
    mer = mer.replaceAll('.', '');
    if (minute < 0 || minute > 59) return null;

    if (mer == 'pm' || mer == 'am') {
      if (hour < 1 || hour > 12) return null;
      if (mer == 'pm' && hour < 12) hour += 12;
      if (mer == 'am' && hour == 12) hour = 0;
    } else {
      // 24-hour fallback (e.g., "at 17:30")
      if (hour < 0 || hour > 23) return null;
    }

    final now = DateTime.now();
    final baseDate = dayWord == 'tomorrow' ? now.add(const Duration(days: 1)) : now;
    final dt = DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
    return dt;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Voice Note'),
        backgroundColor: const Color(0xFF6200EE),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Waveform Visualization',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: 300,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: CustomPaint(
                painter: WaveformPainter(_isRecording),
                child: Center(
                  child: _isRecording
                      ? const Text(
                          'Recording...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        )
                      : const Text(
                          'Tap to start recording',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              _formatDuration(_duration),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6200EE),
              ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isRecording) ...[
                  IconButton(
                    iconSize: 64,
                    icon: const Icon(Icons.stop_circle),
                    color: Colors.red,
                    onPressed: _isUploading ? null : () => _stopRecording(),
                  ),
                ] else ...[
                  IconButton(
                    iconSize: 64,
                    icon: const Icon(Icons.mic),
                    color: const Color(0xFF6200EE),
                    onPressed: _isUploading ? null : () => _startRecording(),
                  ),
                ],
              ],
            ),
            if (_isUploading) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Uploading and processing...'),
            ],
          ],
        ),
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

  WaveformPainter(this.isRecording);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isRecording ? const Color(0xFF6200EE) : Colors.grey
      ..strokeWidth = 2;

    if (isRecording) {
      // Draw animated waveform
      for (int i = 0; i < 20; i++) {
        final x = (size.width / 20) * i;
        final height = (size.height / 2) * (0.3 + (i % 3) * 0.2);
        canvas.drawLine(
          Offset(x, size.height / 2 - height),
          Offset(x, size.height / 2 + height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
