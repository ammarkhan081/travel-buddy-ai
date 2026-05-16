import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/fastapi_service.dart';
import '../../services/api_exceptions.dart';
import '../../utils/ui_utils.dart';

class EditDiaryEntry extends StatefulWidget {
  final String? entryId;
  final Map<String, dynamic>? initialData;

  const EditDiaryEntry({super.key, this.entryId, this.initialData});

  @override
  State<EditDiaryEntry> createState() => _EditDiaryEntryState();
}

class _EditDiaryEntryState extends State<EditDiaryEntry> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _picker = ImagePicker();
  
  bool _isSaving = false;
  File? _imageFile;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _contentController.text = widget.initialData!['content'] ?? '';
      _existingImageUrl = widget.initialData!['imageUrl'];
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showSnackBar(context, 'Error picking image: $e', isError: true);
      }
    }
  }

  Future<String?> _uploadImage(String userId) async {
    if (_imageFile == null) return _existingImageUrl;

    try {
      final storageRef = FirebaseStorage.instance.ref();
      final imageRef = storageRef.child(
        'diary_images/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg'
      );
      
      final uploadTask = await imageRef.putFile(_imageFile!);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _saveEntry() async {
    if (!_formKey.currentState!.validate()) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to save diary entries')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final apiService = FastApiService();
      String? imageUrl = await _uploadImage(user.uid);
      
      if (widget.entryId == null) {
        // New entry
        await apiService.post('/api/diary/manual', {
          'title': _titleController.text.trim(),
          'content': _contentController.text.trim(),
          'imageUrl': imageUrl,
          'user_id': user.uid,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } else {
        // Update existing entry
        await apiService.put('/api/diary/${widget.entryId}', {
          'title': _titleController.text.trim(),
          'content': _contentController.text.trim(),
          'imageUrl': imageUrl,
        });
      }

      if (mounted) {
        UIFeedback.showSnackBar(
          context, 
          widget.entryId == null ? 'Entry saved!' : 'Entry updated!'
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        String message = 'Error saving entry';
        if (e is ApiResponseException) {
          message = e.message;
        } else {
          message = e.toString();
        }
        UIFeedback.showSnackBar(context, message, isError: true);
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
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNewEntry = widget.entryId == null;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          isNewEntry ? 'New Memory' : 'Edit Memory',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: _isSaving ? null : _saveEntry,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_isSaving ? 'Saving' : 'Save'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.today, size: 16, color: theme.colorScheme.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('EEEE, MMM dd, yyyy').format(DateTime.now()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Title Input
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    hintText: 'Title of your entry',
                    hintStyle: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -1,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Give your memory a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
                const SizedBox(height: 16),

                // Image Selection Section
                if (_imageFile != null || _existingImageUrl != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 24),
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _imageFile != null
                              ? Image.file(_imageFile!, fit: BoxFit.cover)
                              : Image.network(_existingImageUrl!, fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.black.withOpacity(0.5),
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => setState(() {
                                _imageFile = null;
                                _existingImageUrl = null;
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withOpacity(0.8),
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, 
                            color: theme.colorScheme.primary),
                          const SizedBox(width: 12),
                          Text(
                            'Add a photo',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Content Input
                TextFormField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    hintText: 'Start writing your thoughts here...',
                    hintStyle: TextStyle(
                      fontSize: 17,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  maxLines: null,
                  minLines: 15,
                  style: TextStyle(
                    fontSize: 17,
                    color: theme.colorScheme.onSurface,
                    height: 1.6,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'The best part is the content!';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 40),
                
                // Bottom Save Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveEntry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 2,
                      shadowColor: theme.colorScheme.primary.withOpacity(0.4),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.save_outlined),
                              const SizedBox(width: 12),
                              Text(
                                'Save Entry',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

