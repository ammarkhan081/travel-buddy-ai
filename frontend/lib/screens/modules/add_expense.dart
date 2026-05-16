import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../services/fastapi_service.dart';
import '../../utils/ui_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

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
  String _selectedCategory = 'Food & Dining';
  String _selectedMethod = 'Manual';
  bool _isSaving = false;
  
  // Voice recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  bool _isProcessingVoice = false;
  bool _isProcessingOCR = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  final List<String> _categories = [
    'Food & Dining',
    'Transportation',
    'Shopping',
    'Bills & Utilities',
    'Entertainment',
    'Other',
  ];

  final List<String> _methods = ['Manual', 'Voice', 'OCR'];

  String _mapBackendCategoryToUi(String rawCategory) {
    final c = rawCategory.trim().toLowerCase();
    if (c == 'food' || c == 'restaurant' || c == 'cafe' || c == 'dining') {
      return 'Food & Dining';
    }
    if (c == 'transport' || c == 'transportation' || c == 'taxi' || c == 'uber' || c == 'bus' || c == 'train' || c == 'flight') {
      return 'Transportation';
    }
    if (c == 'shopping' || c == 'shop') {
      return 'Shopping';
    }
    if (c == 'entertainment' || c == 'tour' || c == 'museum' || c == 'activity') {
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
      UIFeedback.showSnackBar(context, 'Please log in to add expenses', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final amountStr = _amountController.text.trim();
      final amount = double.tryParse(amountStr);
      if (amount == null || amount <= 0) {
        UIFeedback.showSnackBar(
          context,
          'Please enter a valid amount greater than 0',
          isError: true,
        );
        setState(() { _isSaving = false; });
        return;
      }

      final apiService = FastApiService();
      await apiService.post('/api/expenses/', {
        'amount': amount,
        'category': _selectedCategory,
        'description': _descriptionController.text.trim(),
        'date': DateTime.now().toIso8601String(),
        'user_id': user.uid,
      });

      if (mounted) {
        UIFeedback.showSnackBar(context, 'Expense added successfully!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error adding expense: $e', isError: true);
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
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense'),
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
              const Text(
                'Input Method',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: _methods.map((method) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: ChoiceChip(
                        label: Text(method),
                        selected: _selectedMethod == method,
                        onSelected: (selected) {
                          setState(() {
                            _selectedMethod = method;
                          });
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              if (_selectedMethod == 'Voice')
                _buildVoiceInputSection()
              else if (_selectedMethod == 'OCR')
                _buildOCRInputSection()
              else
                _buildManualInputSection(),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveExpense,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6200EE),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(_isSaving ? 'Saving...' : 'Add Expense'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceInputSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                _isRecording ? Icons.stop_circle : Icons.mic,
                size: 48,
                color: _isRecording ? Colors.red : Colors.purple,
              ),
              const SizedBox(height: 16),
              Text(
                _isRecording ? 'Recording... tap to stop' : 'Tap to record expense',
                style: TextStyle(
                  color: _isRecording ? Colors.red : null,
                  fontWeight: _isRecording ? FontWeight.bold : null,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isProcessingVoice ? null : (_isRecording ? _stopRecording : _startRecording),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : null,
                ),
                child: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
              ),
              if (_isProcessingVoice) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Processing voice - please wait...'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Icon(Icons.attach_money),
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter amount';
            final v = double.tryParse(value);
            if (v == null || v <= 0) return 'Please enter a valid amount (e.g. 250)';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildOCRInputSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(Icons.camera_alt, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              const Text('Scan receipt or bill'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isProcessingOCR ? null : _pickImage,
                icon: const Icon(Icons.camera),
                label: Text(_isProcessingOCR ? 'Scanning...' : 'Take Photo'),
              ),
              if (_selectedImage != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_selectedImage!, height: 150, fit: BoxFit.cover),
                ),
              ],
              if (_isProcessingOCR) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Icon(Icons.attach_money),
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter amount';
            final v = double.tryParse(value);
            if (v == null || v <= 0) return 'Please enter a valid amount (e.g. 250)';
            return null;
          },
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
        });
        _processOcrExpense(File(image.path));
      }
    } catch (e) {
      if (mounted) UIFeedback.showSnackBar(context, 'Error opening camera: $e', isError: true);
    }
  }

  Future<void> _processOcrExpense(File imageFile) async {
    setState(() {
      _isProcessingOCR = true;
    });

    try {
      final apiService = FastApiService();
      // Use the generic postVoice for now as it handles Multipart files
      final result = await apiService.postVoice('/api/expenses/ocr', imageFile);

      if (mounted) {
        final extractedAmount = (result['amount'] ?? 0.0).toDouble();
        final extractedDesc   = result['description']?.toString() ?? '';
        final extractedCatRaw = result['category']?.toString() ?? 'Other';

        setState(() {
          if (extractedAmount > 0) {
            _amountController.text = extractedAmount.toString();
          }
          _descriptionController.text = extractedDesc;
          _selectedCategory = _mapBackendCategoryToUi(extractedCatRaw);
          _isProcessingOCR = false;
        });

        UIFeedback.showSnackBar(context, 'Text extracted successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingOCR = false;
          _selectedMethod = 'Manual';
        });
        UIFeedback.showSnackBar(
          context,
          'OCR processing failed. This might be due to missing API keys on the server. Please enter manually.',
          isError: true,
        );
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/expense_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        setState(() {
          _isRecording = true;
        });
      } else {
        if (mounted) UIFeedback.showSnackBar(context, 'Microphone permission required', isError: true);
      }
    } catch (e) {
      if (mounted) UIFeedback.showSnackBar(context, 'Error starting recording: $e', isError: true);
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });
      if (path != null) {
        _processVoiceExpense(path);
      }
    } catch (e) {
      if (mounted) UIFeedback.showSnackBar(context, 'Error stopping recording: $e', isError: true);
    }
  }

  Future<void> _processVoiceExpense(String path) async {
    setState(() {
      _isProcessingVoice = true;
    });

    try {
      final apiService = FastApiService();
      final result = await apiService.postVoice('/api/expenses/voice', File(path));

      if (mounted) {
        final extractedAmount = (result['amount'] ?? 0.0).toDouble();
        final extractedDesc   = result['description']?.toString() ?? '';
        final extractedCatRaw = result['category']?.toString() ?? 'Other';
        final confidence      = (result['confidence'] ?? 0.0).toDouble();

        setState(() {
          if (extractedAmount > 0) {
            _amountController.text = extractedAmount.toString();
          }
          _descriptionController.text = extractedDesc;

          _selectedCategory = _mapBackendCategoryToUi(extractedCatRaw);
          _isProcessingVoice = false;
        });

        // --- INTELLIGENT AUTO-SAVE FLOW ---
        if (confidence > 0.8 && extractedAmount > 0) {
          UIFeedback.showSnackBar(context, '*** AI Confidence High: Saving Auto-magically!');
          _saveExpense(); // Auto-trigger save
        } else {
          setState(() {
            _selectedMethod = 'Manual'; // Show form for review
          });
          UIFeedback.showSnackBar(
            context,
            confidence > 0 
              ? '! AI uncertain (score: $confidence). Please review and save.'
              : '! Voice received. Please enter amount manually.',
            isError: extractedAmount <= 0,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingVoice = false;
          _selectedMethod = 'Manual';
        });
        UIFeedback.showSnackBar(
          context,
          'Voice processing failed. Please enter expense manually.',
          isError: true,
        );
      }
    }
  }

  Widget _buildManualInputSection() {
    return Column(
      children: [
        TextFormField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount',
            prefixIcon: Icon(Icons.attach_money),
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter amount';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category),
            border: OutlineInputBorder(),
          ),
          items: _categories.map((category) {
            return DropdownMenuItem(
              value: category,
              child: Text(category),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedCategory = value!;
            });
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descriptionController,
          decoration: const InputDecoration(
            labelText: 'Description',
            prefixIcon: Icon(Icons.description),
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
      ],
    );
  }
}

