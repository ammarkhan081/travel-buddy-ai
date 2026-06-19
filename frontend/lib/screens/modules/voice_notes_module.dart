import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';
import '../../widgets/module_fab.dart';

/// Voice Notes — list + search + delete + open detail + record CTA.
/// Backend endpoints preserved:
///   GET    /api/voice-notes/    (with ?q= search support)
///   DELETE /api/voice-notes/{id}
class VoiceNotesModule extends StatefulWidget {
  const VoiceNotesModule({super.key});

  @override
  State<VoiceNotesModule> createState() => _VoiceNotesModuleState();
}

class _VoiceNotesModuleState extends State<VoiceNotesModule> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (user == null) {
      return Scaffold(
        body: Column(
          children: [
            AppHeader(
              title: 'Voice Notes',
              subtitle: 'Sign in to view your voice notes',
              onBack: () => Navigator.maybePop(context),
            ),
            const Expanded(
              child: Center(child: Text('Please log in to view voice notes')),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: ModuleFab(
        icon: Icons.mic_rounded,
        label: 'Record',
        minWidth: 126,
        onPressed: () async {
          final result = await Navigator.pushNamed(context, '/recordVoiceNote');
          if (!mounted) return;
          if (result == true) setState(() {});
        },
      ),
      body: Column(
        children: [
          AppHeader(
            title: 'Voice Notes',
            subtitle: 'Speak it. Transcribe it. Keep it.',
            onBack: () => Navigator.maybePop(context),
            trailing: AppHeaderIconButton(
              icon: Icons.refresh_rounded,
              onTap: () => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: _searchField(isDark),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: FastApiService()
                  .get(
                    '/api/voice-notes/',
                    queryParams: _query.isEmpty ? null : {'q': _query},
                  )
                  .then((res) => res as List<dynamic>),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppEmptyState(
                        icon: Icons.error_outline,
                        title: 'Couldn\'t load voice notes',
                        subtitle: 'Pull down to retry.\n${snapshot.error}',
                      ),
                    ),
                  );
                }
                final notes = (snapshot.data ?? const [])
                    .whereType<Map>()
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList();

                if (notes.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppEmptyState(
                        icon: Icons.mic_none_rounded,
                        title: _query.isEmpty
                            ? 'No voice notes yet'
                            : 'No notes match "$_query"',
                        subtitle: _query.isEmpty
                            ? 'Tap "Record" to capture and transcribe your first note.'
                            : 'Try a different search term or clear the search.',
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => setState(() {}),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _VoiceNoteTile(
                      data: notes[i],
                      onTap: () => _openDetail(notes[i]),
                      onDelete: () => _deleteNote(notes[i]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField(bool isDark) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => setState(() => _query = v.trim()),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search transcripts…',
        prefixIcon: Icon(
          Icons.search,
          color: isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    );
  }

  void _openDetail(Map<String, dynamic> data) {
    final transcript = (data['transcript'] ?? '').toString();
    final keywords = (data['keywords'] ?? '').toString();
    final ts = (data['timestamp'] ?? data['created_at'] ?? '').toString();
    final dt = DateTime.tryParse(ts) ?? DateTime.now();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadii.xl),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEE, d MMM yyyy').format(dt),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            DateFormat('h:mm a').format(dt),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (keywords.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: keywords
                        .split(',')
                        .map((k) => k.trim())
                        .where((k) => k.isNotEmpty)
                        .map(
                          (k) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            child: Text(
                              '#$k',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    child: Text(
                      transcript.isEmpty ? 'Transcript was empty.' : transcript,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _deleteNote(data);
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: AppColors.danger,
                            ),
                            label: const Text(
                              'Delete',
                              style: TextStyle(
                                color: AppColors.danger,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: AppColors.danger,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.check),
                            label: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteNote(Map<String, dynamic> data) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Permanently delete this transcribed note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FastApiService().delete('/api/voice-notes/${data['id']}');
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(context, 'Error deleting: $e', isError: true);
    }
  }
}

class _VoiceNoteTile extends StatelessWidget {
  const _VoiceNoteTile({
    required this.data,
    required this.onTap,
    required this.onDelete,
  });
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final transcript = (data['transcript'] ?? '').toString();
    final keywords = (data['keywords'] ?? '').toString();
    final ts = (data['timestamp'] ?? data['created_at'] ?? '').toString();
    final dt = DateTime.tryParse(ts) ?? DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        transcript.isEmpty ? 'No transcript' : transcript,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 12,
                            color: isDark
                                ? AppColors.textTertiaryDark
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d • h:mm a').format(dt),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (keywords.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.label_important_outline,
                              size: 12,
                              color: isDark
                                  ? AppColors.textTertiaryDark
                                  : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                keywords,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onDelete,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
