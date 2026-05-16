import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fyp/screens/modules/profile_settings.dart';

import '../services/auth_service.dart';


class DashboardDrawer extends StatefulWidget {
  final AuthService authService;
  final String userName;
  final String userEmail;
  final String userInitials;
  final VoidCallback loadUserData;

  const DashboardDrawer({
    super.key,
    required this.authService,
    required this.userName,
    required this.userEmail,
    required this.userInitials,
    required this.loadUserData,
  });

  @override
  State<DashboardDrawer> createState() => _DashboardDrawerState();
}

class _DashboardDrawerState extends State<DashboardDrawer>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showFeedbackPanel() {
    _overlayEntry = OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        return Stack(
          children: [
            GestureDetector(
              onTap: _closePanel,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: Container(color: Colors.black.withValues(alpha: 0.15)),
              ),
            ),
            Positioned(
              top: 120,
              right: 20,
              child: SlideTransition(
                position: _offsetAnimation,
                child: Container(
                  width: 230,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(35),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _panelItem(Icons.feedback, "Submit Feedback", () {
                        _closePanel();
                        Navigator.pushNamed(context, "/feedback");
                      }),
                      const SizedBox(height: 10),
                      _panelItem(Icons.bug_report, "Report Issue", () {
                        _closePanel();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("Report feature coming soon")),
                        );
                      }),
                      const SizedBox(height: 10),
                      _panelItem(Icons.email, "Contact Us", () {
                        _closePanel();
                        _showContactDialog(context);
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    _controller.forward();
  }

  void _closePanel() {
    _controller.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  Widget _panelItem(IconData icon, String text, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurface, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Contact Us'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Write your message...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('You can also contact us at amnak6303@gmail.com'),
                  ),
                );
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDrawerTile(IconData icon, String title, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.onSurface),
            const SizedBox(width: 12),
            Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface))),
            Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: Container(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const ProfileSettings()),
                      ).then((_) => widget.loadUserData());
                    },
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: Center(
                        child: widget.userInitials.isNotEmpty
                            ? Text(widget.userInitials,
                                style: TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimaryContainer))
                            : Icon(Icons.person,
                                size: 40, color: theme.colorScheme.onPrimaryContainer),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(widget.userName,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(widget.userEmail,
                      style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  _buildDrawerTile(Icons.home_rounded, 'Home', () => Navigator.pop(context)),
                  _buildDrawerTile(Icons.chat_bubble_outline, 'Chat',
                          () => Navigator.pushNamed(context, '/chat')),
                  _buildDrawerTile(Icons.notifications_active, 'Alerts',
                          () => Navigator.pushNamed(context, '/alerts')),
                  _buildDrawerTile(Icons.alarm, 'Reminders',
                          () => Navigator.pushNamed(context, '/reminders')),
                  _buildDrawerTile(Icons.book, 'Diary',
                          () => Navigator.pushNamed(context, '/diary')),
                  _buildDrawerTile(Icons.mic, 'Voice Notes',
                          () => Navigator.pushNamed(context, '/voiceNotes')),
                  _buildDrawerTile(Icons.account_balance_wallet, 'Expenses',
                          () => Navigator.pushNamed(context, '/expenseTracker')),
                  const SizedBox(height: 16),
                  _buildDrawerTile(Icons.feedback, 'Feedback', _showFeedbackPanel),
                  const SizedBox(height: 16),
                  _buildDrawerTile(Icons.logout, 'Logout', () async {
                    await widget.authService.signOut();
                    if (!context.mounted) return;
                    Navigator.pushReplacementNamed(context, '/login');
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
