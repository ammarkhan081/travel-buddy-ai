import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isLoading = false;
  File? _profileImage;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _changeProfilePicture() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            if (_profileImage != null || _profileImageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  setState(() {
                    _profileImage = null;
                    _profileImageUrl = null;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Photo removed')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null && mounted) {
        setState(() {
          _profileImage = File(image.path);
          _profileImageUrl = null; // Clear old URL when new image is selected
        });
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile picture ${source == ImageSource.camera ? 'taken' : 'selected'}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _loadUserData() async {
    final user = _authService.currentUser;
    if (user != null) {
      _nameController = TextEditingController(text: user.displayName ?? '');
      _emailController = TextEditingController(text: user.email ?? '');

      // Load profile picture from Firestore - use doc() instead of query for better performance
      try {
        final userDocRef = _firestore.collection('users').doc(user.uid);
        final userDoc = await userDocRef.get();
        if (userDoc.exists && mounted) {
          final data = userDoc.data()!;
          setState(() {
            _profileImageUrl = data['profileImageUrl'];
            _phoneController.text = data['phone'] ?? '';
            _bioController.text = data['bio'] ?? '';
          });
        }
      } catch (e) {
        // Ignore errors loading profile image
      }
    } else {
      _nameController = TextEditingController();
      _emailController = TextEditingController();
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final user = _authService.currentUser;
        if (user == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please log in to save profile')),
            );
          }
          return;
        }

        String? imageUrl = _profileImageUrl;

        // Upload new profile picture if selected
        if (_profileImage != null) {
          try {
            // Show upload progress
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 16),
                      Text('Uploading profile picture...'),
                    ],
                  ),
                  duration: Duration(seconds: 30),
                ),
              );
            }

            final ref = _storage.ref().child(
              'profile_pictures/${user.uid}.jpg',
            );

            // Upload with metadata
            final uploadTask = ref.putFile(
              _profileImage!,
              SettableMetadata(
                contentType: 'image/jpeg',
                cacheControl: 'max-age=31536000',
              ),
            );

            // Wait for upload to complete
            final snapshot = await uploadTask;
            imageUrl = await snapshot.ref.getDownloadURL();

            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error uploading image: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }

        // Update display name
        try {
          await user.updateDisplayName(_nameController.text.trim());
          await user.reload();
        } catch (e) {
          // Continue even if display name update fails
        }

        // Save to Firestore using doc() instead of query
        final userDocRef = _firestore.collection('users').doc(user.uid);
        final userDoc = await userDocRef.get();

        if (userDoc.exists) {
          await userDocRef.update({
            'name': _nameController.text.trim(),
            'email': user.email ?? '',
            'profileImageUrl': imageUrl,
            'phone': _phoneController.text.trim(),
            'bio': _bioController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await userDocRef.set({
            'uid': user.uid,
            'name': _nameController.text.trim(),
            'email': user.email ?? '',
            'profileImageUrl': imageUrl,
            'phone': _phoneController.text.trim(),
            'bio': _bioController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, {
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'profileImageUrl': imageUrl,
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating profile: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
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
            title: 'Edit Profile',
            subtitle: 'Keep your travel profile current',
            onBack: () => Navigator.maybePop(context),
            trailing: AppHeaderIconButton(
              icon: Icons.check_rounded,
              onTap: _isLoading ? () {} : _saveProfile,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        boxShadow: isDark ? const [] : AppShadows.softCard,
                      ),
                      child: Column(
                        children: [
                          _buildAvatar(context, isDark),
                          const SizedBox(height: 18),
                          Text(
                            'Tap the camera badge to update your photo',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        boxShadow: isDark ? const [] : AppShadows.softCard,
                      ),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              prefixIcon: Icon(Icons.phone),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _bioController,
                            decoration: const InputDecoration(
                              labelText: 'Bio',
                              prefixIcon: Icon(Icons.description),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Save Changes'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, bool isDark) {
    final theme = Theme.of(context);
    final initials = _nameController.text.isNotEmpty
        ? _nameController.text
              .split(' ')
              .map((n) => n.isNotEmpty ? n[0] : '')
              .take(2)
              .join()
              .toUpperCase()
        : 'U';

    return Stack(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            gradient: _profileImage == null && _profileImageUrl == null
                ? AppGradients.primary
                : null,
            color: _profileImage != null || _profileImageUrl != null
                ? null
                : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: isDark ? const [] : AppShadows.raisedCard,
          ),
          child: _profileImage != null
              ? ClipOval(
                  child: Image.file(
                    _profileImage!,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                )
              : _profileImageUrl != null
              ? ClipOval(
                  child: Image.network(
                    _profileImageUrl!,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                )
              : Center(
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _changeProfilePicture,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
                boxShadow: isDark ? const [] : AppShadows.softCard,
              ),
              child: const Icon(
                Icons.camera_alt,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
