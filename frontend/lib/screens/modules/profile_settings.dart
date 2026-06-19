import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fyp/screens/login_screen.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import 'edit_profile_screen.dart';
import 'change_email_screen.dart';
import 'change_password_screen.dart';
import 'notifications_settings_screen.dart';
import 'theme_settings_screen.dart';
import 'language_settings_screen.dart';
import 'my_bookings_screen.dart';
// Make sure this path is correct

class ProfileSettings extends StatefulWidget {
  const ProfileSettings({super.key});

  @override
  State<ProfileSettings> createState() => _ProfileSettingsState();
}

class _ProfileSettingsState extends State<ProfileSettings> {
  final AuthService _authService = AuthService();
  final ImagePicker _imagePicker = ImagePicker();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _userName = 'Amna';
  String _userEmail = 'amnakhan@gmail.com';
  String _userBio = '';
  File? _profileImage;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserData());
  }

  Future<void> _loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user != null && mounted) {
        String? firestoreProfileImage;
        try {
          final doc = await _firestore.collection('users').doc(user.uid).get();
          if (doc.exists) {
            final data = doc.data();
            firestoreProfileImage = data?['profileImageUrl'] as String?;
            setState(() {
              _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
              _userEmail = user.email ?? 'No email';
              _userBio = (data?['bio'] as String?)?.trim() ?? '';
              _profileImageUrl = firestoreProfileImage ?? user.photoURL;
            });
            return;
          }
        } catch (_) {}

        setState(() {
          _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
          _userEmail = user.email ?? 'No email';
          _userBio = '';
          _profileImageUrl = firestoreProfileImage ?? user.photoURL;
        });
      }
    } catch (e) {
      if (mounted) {
        final user = _authService.currentUser;
        if (user != null) {
          setState(() {
            _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
            _userEmail = user.email ?? 'No email';
            _profileImageUrl = user.photoURL;
          });
        }
      }
    }
  }

  void _changeProfilePicture() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProfilePicOption(
              Icons.camera_alt,
              'Take Photo',
              () => _pickImage(ImageSource.camera),
            ),
            _buildProfilePicOption(
              Icons.photo_library,
              'Choose from Gallery',
              () => _pickImage(ImageSource.gallery),
            ),
            if (_profileImage != null ||
                (_profileImageUrl != null && _profileImageUrl!.isNotEmpty))
              _buildProfilePicOption(Icons.delete, 'Remove Photo', () async {
                Navigator.pop(context);
                setState(() {
                  _profileImage = null;
                  _profileImageUrl = null;
                });
                final user = _authService.currentUser;
                if (user != null) {
                  try {
                    await Future.wait([
                      user.updatePhotoURL(null),
                      _firestore.collection('users').doc(user.uid).set({
                        'profileImageUrl': null,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true)),
                    ]);
                  } catch (_) {}
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile photo removed.')),
                  );
                }
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    XFile? image;
    try {
      image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not access camera/gallery: $e')),
        );
      }
      return;
    }

    if (image == null || !mounted) return;
    Navigator.pop(context);

    final file = File(image.path);
    setState(() => _profileImage = file);

    // Upload to Firebase Storage and persist URL to Firestore
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('profile_pictures')
          .child('${user.uid}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await Future.wait([
        user.updatePhotoURL(url),
        _firestore.collection('users').doc(user.uid).set({
          'profileImageUrl': url,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      ]);

      if (mounted) setState(() => _profileImageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo saved locally. Upload failed — check your connection.',
            ),
          ),
        );
      }
    }
  }

  Widget _buildProfilePicOption(
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.iconTheme.color),
      title: Text(title, style: theme.textTheme.bodyMedium),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? theme.colorScheme.onSurface : Colors.white,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileHeader(theme),
            const SizedBox(height: 12),
            _buildSettingsSection('My Travel', [
              _buildSettingsTile(Icons.luggage, 'My Bookings', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
                );
              }, theme: theme),
            ]),
            const SizedBox(height: 16),
            _buildSettingsSection('Account', [
              _buildSettingsTile(Icons.person, 'Edit Profile', () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfileScreen(),
                  ),
                );
                if (result != null && mounted) _loadUserData();
              }, theme: theme),
              _buildSettingsTile(Icons.email, 'Change Email', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChangeEmailScreen()),
                );
              }, theme: theme),
              _buildSettingsTile(Icons.lock, 'Change Password', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              }, theme: theme),
            ]),
            _buildSettingsSection('Preferences', [
              _buildSettingsTile(Icons.notifications, 'Notifications', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NotificationsSettingsScreen(),
                  ),
                );
              }, theme: theme),
              _buildSettingsTile(Icons.dark_mode, 'Theme', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ThemeSettingsScreen(),
                  ),
                );
              }, theme: theme),
              _buildSettingsTile(Icons.language, 'Language', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LanguageSettingsScreen(),
                  ),
                );
              }, theme: theme),
            ]),
            _buildSettingsSection('About', [
              _buildSettingsTile(
                Icons.info_outline,
                'App Version',
                () {},
                trailing: Text('1.0.0', style: theme.textTheme.bodySmall),
                theme: theme,
              ),
              _buildSettingsTile(Icons.privacy_tip, 'Privacy Policy', () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Privacy Policy')));
              }, theme: theme),
              _buildSettingsTile(Icons.help, 'Help & Support', () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Help & Support')));
              }, theme: theme),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await _authService.signOut();
                    if (!context.mounted) return;
                    // Navigate to LoginScreen and remove all previous routes
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error signing out: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: isDark
                      ? theme.colorScheme.primary
                      : AppColors.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Logout',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final initials = _userName.isNotEmpty
        ? _userName.split(' ').map((n) => n[0]).take(2).join().toUpperCase()
        : 'U';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 110, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF1A1042), AppColors.surfaceDark]
              : const [
                  AppColors.primary,
                  AppColors.primaryLight,
                  AppColors.accentPink,
                ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(26),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _changeProfilePicture,
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 52,
                    backgroundColor: isDark
                        ? theme.colorScheme.surface
                        : Colors.white,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : (_profileImageUrl != null &&
                                      _profileImageUrl!.isNotEmpty
                                  ? NetworkImage(_profileImageUrl!)
                                  : null)
                              as ImageProvider<Object>?,
                    child:
                        _profileImage == null &&
                            (_profileImageUrl == null ||
                                _profileImageUrl!.isEmpty)
                        ? Text(
                            initials,
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? theme.colorScheme.onSurface
                                  : AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? theme.colorScheme.surface : Colors.white,
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      color: isDark
                          ? theme.colorScheme.onSurface
                          : AppColors.primary,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _userName,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark ? theme.colorScheme.onSurface : Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _userEmail,
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? theme.colorScheme.onSurfaceVariant
                  : Colors.white.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
          if (_userBio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      )
                    : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                _userBio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? theme.colorScheme.onSurface : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surface.withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white10 : Colors.white),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? theme.colorScheme.onSurface
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    IconData icon,
    String title,
    VoidCallback onTap, {
    Widget? trailing,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : AppColors.bgLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: isDark
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isDark ? theme.colorScheme.primary : AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        trailing:
            trailing ??
            Icon(
              Icons.chevron_right,
              color: isDark
                  ? theme.colorScheme.onSurfaceVariant
                  : AppColors.primary,
            ),
        onTap: onTap,
      ),
    );
  }
}
