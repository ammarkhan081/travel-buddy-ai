import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';

/// Add Expense — three input methods (Manual, Voice, OCR receipt).
/// All backend endpoints + logic preserved.
class AddExpense extends StatefulWidget {
  const AddExpense({super.key});

  @override
  State<AddExpense> createState() => _AddExpenseState();
}

class _AddExpenseState extends State<AddExpense> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();

  String _selectedCategory = 'Food & Dining';
  // AI-extracted, non-visual: carried into the save body so the chatbot can
  // answer "how much on food at <hotel>". Cleared when switching to Manual.
  String? _extractedMerchant;
  String? _extractedLocation;
  String _selectedMethod = 'Manual';
  bool _isSaving = false;
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  bool _isProcessingOCR = false;
  File? _selectedImage;

  final List<String> _categories = const [
    'Food & Dining',
    'Transportation',
    'Shopping',
    'Bills & Utilities',
    'Entertainment',
    'Other',
  ];

  static const _methods = <(String, IconData)>[
    ('Manual', Icons.edit_rounded),
    ('Voice', Icons.mic_rounded),
    ('OCR', Icons.document_scanner_rounded),
  ];

  String _mapBackendCategoryToUi(String rawCategory) {
    final c = rawCategory.trim().toLowerCase();
    if (c == 'food' ||
        c == 'restaurant' ||
        c == 'cafe' ||
        c == 'dining') {
      return 'Food & Dining';
    }
    if (c == 'transport' ||
        c == 'transportation' ||
        c == 'taxi' ||
        c == 'uber' ||
        c == 'bus' ||
        c == 'train' ||
        c == 'flight') {
      return 'Transportation';
    }
    if (c == 'shopping' || c == 'shop') return 'Shopping';
    if (c == 'entertainment' ||
        c == 'tour' ||
        c == 'museum' ||
        c == 'activity') {
      return 'Entertainment';
    }
    if (c == 'bills' || c == 'utilities' || c == 'bills & utilities') {
      return 'Bills & Utilities';
    }
    return 'Other';
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;
    final user = _auth.currentUser;
    if (user == null) {
      UIFeedback.showSnackBar(context, 'Please log in to add expenses',
          isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final amount = double.tryParse(_amountController.text.trim());
      if (amount == null || amount <= 0) {
        UIFeedback.showSnackBar(
            context, 'Please enter a valid amount > 0',
            isError: true);
        setState(() => _isSaving = false);
        return;
      }
      await FastApiService().post('/api/expenses/', {
        'amount': amount,
        'category': _selectedCategory,
        'description': _descriptionController.text.trim(),
        'date': DateTime.now().toIso8601String(),
        'user_id': user.uid,
        if (_extractedMerchant != null && _extractedMerchant!.trim().isNotEmpty)
          'merchant': _extractedMerchant!.trim(),
        if (_extractedLocation != null && _extractedLocation!.trim().isNotEmpty)
          'location': _extractedLocation!.trim(),
      });
      if (!mounted) return;
      UIFeedback.showSnackBar(context, 'Expense added successfully!');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error adding expense: $e',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Voice ────────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path =
            '${directory.path}/expense_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() => _isRecording = true);
      } else {
        if (mounted) {
          UIFeedback.showSnackBar(context, 'Microphone permission required',
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error starting recording: $e',
            isError: true);
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (path != null) _processVoiceExpense(path);
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error stopping recording: $e',
            isError: true);
      }
    }
  }

  Future<void> _processVoiceExpense(String path) async {
    setState(() => _isProcessingVoice = true);
    try {
      final result = await FastApiService()
          .postVoice('/api/expenses/voice', File(path));
      if (!mounted) return;
      final extractedAmount = (result['amount'] ?? 0.0).toDouble();
      final extractedDesc = result['description']?.toString() ?? '';
      final extractedCatRaw = result['category']?.toString() ?? 'Other';
      final confidence = (result['confidence'] ?? 0.0).toDouble();
      setState(() {
        if (extractedAmount > 0) {
          _amountController.text = extractedAmount.toString();
        }
        _descriptionController.text = extractedDesc;
        _selectedCategory = _mapBackendCategoryToUi(extractedCatRaw);
        _extractedMerchant = result['merchant']?.toString();
        _extractedLocation = result['location']?.toString();
        _isProcessingVoice = false;
      });
      if (confidence > 0.8 && extractedAmount > 0) {
        UIFeedback.showSnackBar(
            context, '✨ AI confidence high — saving automatically');
        _saveExpense();
      } else {
        setState(() => _selectedMethod = 'Manual');
        UIFeedback.showSnackBar(
          context,
          confidence > 0
              ? 'AI uncertain — please review and save.'
              : 'Voice received — please enter amount manually.',
          isError: extractedAmount <= 0,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessingVoice = false;
        _selectedMethod = 'Manual';
      });
      UIFeedback.showSnackBar(
          context, 'Voice processing failed. Please enter manually.',
          isError: true);
    }
  }

  // ── OCR ──────────────────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (image != null) {
        setState(() => _selectedImage = File(image.path));
        _processOcrExpense(File(image.path));
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error opening camera: $e',
            isError: true);
      }
    }
  }

  Future<void> _processOcrExpense(File imageFile) async {
    setState(() => _isProcessingOCR = true);
    try {
      final result =
          await FastApiService().postVoice('/api/expenses/ocr', imageFile);
      if (!mounted) return;
      final extractedAmount = (result['amount'] ?? 0.0).toDouble();
      final extractedDesc = result['description']?.toString() ?? '';
      final extractedCatRaw = result['category']?.toString() ?? 'Other';
      setState(() {
        if (extractedAmount > 0) {
          _amountController.text = extractedAmount.toString();
        }
        _descriptionController.text = extractedDesc;
        _selectedCategory = _mapBackendCategoryToUi(extractedCatRaw);
        _extractedMerchant = result['merchant']?.toString();
        _extractedLocation = result['location']?.toString();
        _isProcessingOCR = false;
      });
      UIFeedback.showSnackBar(context, 'Text extracted from receipt');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessingOCR = false;
        _selectedMethod = 'Manual';
      });
      UIFeedback.showSnackBar(
        context,
        'OCR failed (server may be missing API key). Enter manually.',
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'New Expense',
            subtitle: 'Type it, say it, or scan a receipt',
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
                    // Method toggle
                    _card(
                      isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionLabel('Input method', isDark),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              for (final m in _methods) ...[
                                if (m != _methods.first)
                                  const SizedBox(width: 8),
                                Expanded(
                                  child: _methodChip(m.$1, m.$2, isDark),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_selectedMethod == 'Voice')
                      _voiceCard(isDark)
                    else if (_selectedMethod == 'OCR')
                      _ocrCard(isDark)
                    else
                      _manualCard(isDark),
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveExpense,
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
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_isSaving ? 'Saving…' : 'Add Expense'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _methodChip(String label, IconData icon, bool isDark) {
    final active = _selectedMethod == label;
    return Material(
      color: active
          ? AppColors.primary
          : (isDark ? AppColors.surfaceDarkElevated : AppColors.bgLight),
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => setState(() {
          _selectedMethod = label;
          if (label == 'Manual') {
            _extractedMerchant = null;
            _extractedLocation = null;
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: active
                      ? Colors.white
                      : AppColors.primary,
                  size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active
                      ? Colors.white
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

  Widget _manualCard(bool isDark) {
    return _card(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Details', isDark),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'Amount (PKR)',
              prefixIcon: const Icon(Icons.payments_outlined,
                  color: AppColors.primary),
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.bgLight,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter amount';
              final v = double.tryParse(value);
              if (v == null || v <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.category_rounded,
                  color: AppColors.primary),
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.bgLight,
            ),
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _selectedCategory = v!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Description (optional)',
              prefixIcon: const Icon(Icons.notes,
                  color: AppColors.primary),
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.bgLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _voiceCard(bool isDark) {
    return _card(
      isDark,
      child: Column(
        children: [
          GestureDetector(
            onTap: _isProcessingVoice
                ? null
                : (_isRecording ? _stopRecording : _startRecording),
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isRecording
                      ? const [Color(0xFFFF7B95), AppColors.danger]
                      : const [Color(0xFF7B5AFF), AppColors.primaryDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording
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
                size: 60,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _isRecording
                ? 'Recording… tap to stop'
                : 'Tap to record your expense',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          if (_isProcessingVoice) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Processing voice…',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 18),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'Amount (PKR)',
              prefixIcon: const Icon(Icons.payments_outlined,
                  color: AppColors.primary),
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.bgLight,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter amount';
              final v = double.tryParse(value);
              if (v == null || v <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _ocrCard(bool isDark) {
    return _card(
      isDark,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.infoBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              children: [
                const Icon(Icons.document_scanner_rounded,
                    color: AppColors.infoBlue, size: 44),
                const SizedBox(height: 10),
                Text(
                  'Scan a receipt',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'AI extracts amount, category and description.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _isProcessingOCR ? null : _pickImage,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(
                      _isProcessingOCR ? 'Scanning…' : 'Take Photo'),
                ),
              ],
            ),
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Image.file(_selectedImage!,
                  height: 160, fit: BoxFit.cover),
            ),
          ],
          if (_isProcessingOCR) ...[
            const SizedBox(height: 14),
            const CircularProgressIndicator(),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'Amount (PKR)',
              prefixIcon: const Icon(Icons.payments_outlined,
                  color: AppColors.primary),
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.bgLight,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter amount';
              final v = double.tryParse(value);
              if (v == null || v <= 0) return 'Enter a valid amount';
              return null;
            },
          ),
        ],
      ),
    );
  }
}
