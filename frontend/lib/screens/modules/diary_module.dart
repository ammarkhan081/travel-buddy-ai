import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../services/active_journey.dart';
import '../../services/api_exceptions.dart';
import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/date_utils.dart' as fyp_date;
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';
import '../../widgets/module_fab.dart';
import 'edit_diary_entry.dart';

/// Travel Diary — list, search, date-filter, AI auto-generate, edit, delete.
/// Endpoints preserved:
///   GET    /api/diary/
///   POST   /api/diary/auto-generate    (with optional lat/lon)
///   DELETE /api/diary/{id}
class DiaryModule extends StatefulWidget {
  const DiaryModule({super.key});

  @override
  State<DiaryModule> createState() => _DiaryModuleState();
}

class _DiaryModuleState extends State<DiaryModule> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();

  bool _isGenerating = false;
  DateTime? _selectedDate;
  List<Map<String, dynamic>> _allEntries = [];
  List<Map<String, dynamic>> _filteredEntries = [];
  Future<List<Map<String, dynamic>>>? _diaryFuture;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilters);
    _fetchDiary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _fetchDiary() {
    setState(() {
      _diaryFuture = FastApiService()
          .get('/api/diary/')
          .then<List<Map<String, dynamic>>>((res) {
            final list =
                (res as List)
                    .whereType<Map>()
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList()
                  ..sort((a, b) {
                    final aT = DateTime.tryParse(
                      (a['timestamp'] ?? '').toString(),
                    );
                    final bT = DateTime.tryParse(
                      (b['timestamp'] ?? '').toString(),
                    );
                    if (aT == null && bT == null) return 0;
                    if (aT == null) return 1;
                    if (bT == null) return -1;
                    return bT.compareTo(aT);
                  });
            _allEntries = list;
            _filteredEntries = list;
            return list;
          });
    });
  }

  void _applyFilters() {
    final q = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredEntries = _allEntries.where((entry) {
        final title = (entry['title'] ?? '').toString().toLowerCase();
        final content = (entry['content'] ?? '').toString().toLowerCase();
        final matchesQuery =
            q.isEmpty || title.contains(q) || content.contains(q);
        if (_selectedDate != null) {
          final entryDate = DateTime.tryParse(
            (entry['timestamp'] ?? '').toString(),
          );
          if (entryDate == null) return false;
          final ed = DateTime(entryDate.year, entryDate.month, entryDate.day);
          final sd = DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
          );
          return matchesQuery && ed.isAtSameMomentAs(sd);
        }
        return matchesQuery;
      }).toList();
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _applyFilters();
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedDate = null;
      _searchController.clear();
      _filteredEntries = _allEntries;
    });
  }

  Future<Position?> _fetchLocationSafely() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _generateAiDiary() async {
    final user = _auth.currentUser;
    if (user == null) return;
    setState(() => _isGenerating = true);
    try {
      // Fetch GPS and active journey in parallel
      final results = await Future.wait([
        _fetchLocationSafely(),
        ActiveJourney.load(),
      ]);
      final pos = results[0] as Position?;
      final journey = results[1] as ActiveJourneyData?;

      final payload = <String, dynamic>{'user_id': user.uid, 'days': 1};

      if (pos != null) {
        payload['latitude'] = pos.latitude;
        payload['longitude'] = pos.longitude;
      }

      // Pass active journey context so the backend can weave it into the diary
      if (journey != null) {
        payload['journey_from'] = journey.fromName;
        payload['journey_to'] = journey.toName;
        payload['journey_transport'] = journey.transport;
        payload['journey_departure_time'] =
            journey.departureTime.toIso8601String();
        if (journey.distanceKm != null) {
          payload['journey_distance_km'] = journey.distanceKm;
        }
        if (journey.durationMin != null) {
          payload['journey_duration_min'] = journey.durationMin;
        }
      }

      await FastApiService().post('/api/diary/auto-generate', payload);
      if (!mounted) return;
      UIFeedback.showSnackBar(context, 'AI diary entry generated and saved!');
      _fetchDiary();
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'AI generation failed: $e. Try adding reminders or expenses first.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _showVoiceDiarySheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _VoiceDiarySheet(),
    );
    if (result == true && mounted) {
      UIFeedback.showSnackBar(
        context,
        'Voice diary entry created! Your words, beautifully written.',
      );
      _fetchDiary();
    }
  }

  Future<void> _showManualTripDiarySheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ManualTripDiarySheet(),
    );
    if (result == true && mounted) {
      UIFeedback.showSnackBar(
        context,
        'Trip diary generated! Pull down to refresh.',
      );
      _fetchDiary();
    }
  }

  Future<void> _deleteEntry(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text(
          'Are you sure you want to delete this diary entry? This cannot be undone.',
        ),
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
      await FastApiService().delete('/api/diary/$docId');
      if (!mounted) return;
      UIFeedback.showSnackBar(context, 'Diary entry deleted');
      _fetchDiary();
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'Error deleting entry: $e',
        isError: true,
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        body: Column(
          children: [
            AppHeader(
              title: 'Diary',
              subtitle: 'Sign in to view your diary',
              onBack: () => Navigator.maybePop(context),
            ),
            const Expanded(
              child: Center(child: Text('Please log in to view diary entries')),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: ModuleFab(
        icon: Icons.edit_note_rounded,
        label: 'New Entry',
        minWidth: 140,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const EditDiaryEntry()),
          );
          if (result == true) _fetchDiary();
        },
      ),
      body: Column(
        children: [
          AppHeader(
            title: 'My Diary',
            subtitle: 'Capture your thoughts, create your legacy',
            onBack: () => Navigator.maybePop(context),
            actions: [
              AppHeaderIconButton(
                icon: Icons.calendar_month_rounded,
                onTap: _selectDate,
              ),
              if (_selectedDate != null || _searchController.text.isNotEmpty)
                AppHeaderIconButton(
                  icon: Icons.filter_list_off_rounded,
                  onTap: _clearFilters,
                ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _fetchDiary(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
                children: [
                  _buildSearchField(isDark),
                  if (_selectedDate != null) ...[
                    const SizedBox(height: 10),
                    _selectedDateChip(),
                  ],
                  const SizedBox(height: 16),
                  _buildAiCard(),
                  const SizedBox(height: 12),
                  _buildVoiceDiaryCard(isDark),
                  const SizedBox(height: 12),
                  _buildTripDiaryCard(isDark),
                  const SizedBox(height: 18),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _diaryFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          _allEntries.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return _buildError(snapshot.error);
                      }
                      if (_allEntries.isEmpty) {
                        return AppEmptyState(
                          icon: Icons.auto_stories_rounded,
                          title: 'Your story begins here',
                          subtitle:
                              'Add reminders & expenses, or write your first entry — your travel memory book starts now.',
                          ctaLabel: 'Write First Entry',
                          onCta: () async {
                            final r = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditDiaryEntry(),
                              ),
                            );
                            if (r == true) _fetchDiary();
                          },
                        );
                      }
                      if (_filteredEntries.isEmpty) {
                        return AppEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No entries match',
                          subtitle:
                              'Try a different search or clear the filters.',
                          ctaLabel: 'Clear filters',
                          onCta: _clearFilters,
                        );
                      }
                      return Column(
                        children: [
                          for (final entry in _filteredEntries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _DiaryEntryCard(
                                data: entry,
                                onTap: () async {
                                  final r = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditDiaryEntry(
                                        entryId: entry['id'].toString(),
                                        initialData: entry,
                                      ),
                                    ),
                                  );
                                  if (r == true) _fetchDiary();
                                },
                                onEdit: () async {
                                  final r = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditDiaryEntry(
                                        entryId: entry['id'].toString(),
                                        initialData: entry,
                                      ),
                                    ),
                                  );
                                  if (r == true) _fetchDiary();
                                },
                                onDelete: () =>
                                    _deleteEntry(entry['id'].toString()),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search your memories…',
        prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => _searchController.clear(),
              ),
      ),
    );
  }

  Widget _selectedDateChip() {
    return Wrap(
      spacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.event_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                DateFormat('MMM d, yyyy').format(_selectedDate!),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  setState(() => _selectedDate = null);
                  _applyFilters();
                },
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceDiaryCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accentPink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: AppColors.accentPink,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Diary',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Speak — AI writes your diary in English',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _showVoiceDiarySheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accentPink,
              side: const BorderSide(color: AppColors.accentPink),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text(
              'Record',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripDiaryCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Diary',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Kumrat, Kalam, or any trip with friends',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _showManualTripDiarySheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text(
              'Generate',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppGradients.primary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppShadows.primaryGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI-Generated Entry',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Summarise today\'s reminders, expenses & notes',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateAiDiary,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isGenerating ? 'Generating…' : 'Generate Summary',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Object? error) {
    String message = 'Failed to load entries';
    if (error is ApiResponseException) message = error.message;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Couldn\'t load entries',
        subtitle: message,
        ctaLabel: 'Retry',
        onCta: _fetchDiary,
      ),
    );
  }
}

class _DiaryEntryCard extends StatelessWidget {
  const _DiaryEntryCard({
    required this.data,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = (data['title'] ?? 'Untitled').toString();
    final content = (data['content'] ?? '').toString();
    // Convert the stored UTC timestamp to the device's local time so the diary
    // shows the real wall-clock time it was created (was showing UTC before).
    final timestamp = fyp_date.DateUtils.parseToLocal(
      (data['timestamp'] ?? '').toString(),
    );
    final location = (data['location'] ?? '').toString();
    final destinationName = (data['destination_name'] ?? '').toString();
    final isAi =
        (data['is_auto_generated'] == true) ||
        title.toLowerCase().contains('ai summary') ||
        title.toLowerCase().contains('travel diary —');
    // trip diaries show as a special AI-generated type
    final isTripDiary = destinationName.isNotEmpty;
    final imageUrl = (data['imageUrl'] ?? '').toString();

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color:
                            (isTripDiary
                                    ? AppColors.primary
                                    : isAi
                                    ? AppColors.accentPink
                                    : AppColors.primary)
                                .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Icon(
                        isTripDiary
                            ? Icons.auto_stories_rounded
                            : isAi
                            ? Icons.auto_awesome
                            : Icons.edit_note_rounded,
                        color: isTripDiary
                            ? AppColors.primary
                            : isAi
                            ? AppColors.accentPink
                            : AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('EEE, d MMM • h:mm a').format(timestamp),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppColors.textTertiary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: AppColors.danger,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Delete',
                                style: TextStyle(color: AppColors.danger),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
                if (imageUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Image.network(
                      imageUrl,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, p) {
                        if (p == null) return child;
                        return Container(
                          height: 160,
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, _, _) => Container(
                        height: 80,
                        color: Colors.grey.shade200,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ],
                if (isAi || isTripDiary || location.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      // Trip diary badge takes priority over generic AI badge
                      if (isTripDiary)
                        _badge(
                          destinationName,
                          AppColors.primary,
                          icon: Icons.map_rounded,
                        )
                      else if (isAi)
                        _badge('AI Summary', AppColors.accentPink),
                      // Show location only if it's different from destination_name
                      if (location.isNotEmpty && location != destinationName)
                        _badge(
                          location,
                          AppColors.infoBlue,
                          icon: Icons.location_on_outlined,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color, {IconData? icon}) {
    // Cap the badge width and let the label ellipsize so a long place name
    // (e.g. a full reverse-geocoded address) can never overflow the card.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Manual Trip Diary Bottom Sheet ────────────────────────────────────────────

class _ManualTripDiarySheet extends StatefulWidget {
  const _ManualTripDiarySheet();

  @override
  State<_ManualTripDiarySheet> createState() => _ManualTripDiarySheetState();
}

class _ManualTripDiarySheetState extends State<_ManualTripDiarySheet> {
  final _destinationController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _returnDate;
  bool _isGenerating = false;

  @override
  void dispose() {
    _destinationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? DateTime.now())
          : (_returnDate ?? (_fromDate ?? DateTime.now())),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          // Clear return date if it's before new from date
          if (_returnDate != null && _returnDate!.isBefore(picked)) {
            _returnDate = null;
          }
        } else {
          _returnDate = picked;
        }
      });
    }
  }

  Future<void> _generate() async {
    final destination = _destinationController.text.trim();
    if (destination.isEmpty) {
      UIFeedback.showSnackBar(
        context,
        'Please enter a destination name.',
        isError: true,
      );
      return;
    }
    if (_fromDate == null) {
      UIFeedback.showSnackBar(
        context,
        'Please select the trip start date.',
        isError: true,
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      await FastApiService().post('/api/diary/trip-diary', {
        'destination_name': destination,
        'from_date': _fromDate!.toIso8601String().split('T').first,
        'return_date': _returnDate?.toIso8601String().split('T').first,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'booking_id': null,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'Could not generate diary: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final df = DateFormat('dd MMM yyyy');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generate Trip Diary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Friend trip, family trip — any trip',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Destination field
            _SheetLabel(text: 'Destination', isDark: isDark),
            const SizedBox(height: 6),
            TextField(
              controller: _destinationController,
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
              decoration: _inputDecoration(
                hint: 'e.g. Kumrat, Kalam, Neelum Valley…',
                isDark: isDark,
              ),
            ),
            const SizedBox(height: 14),

            // Date pickers
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetLabel(text: 'From Date', isDark: isDark),
                      const SizedBox(height: 6),
                      _DatePickerButton(
                        label: _fromDate != null
                            ? df.format(_fromDate!)
                            : 'Select date',
                        icon: Icons.calendar_today_rounded,
                        isDark: isDark,
                        onTap: () => _pickDate(isFrom: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetLabel(
                        text: 'Return Date (optional)',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 6),
                      _DatePickerButton(
                        label: _returnDate != null
                            ? df.format(_returnDate!)
                            : 'Select date',
                        icon: Icons.event_rounded,
                        isDark: isDark,
                        onTap: () => _pickDate(isFrom: false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Notes field
            _SheetLabel(text: 'Memories to include (optional)', isDark: isDark),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
              decoration: _inputDecoration(
                hint: 'Best moments, funny incidents, places visited…',
                isDark: isDark,
              ),
            ),
            const SizedBox(height: 20),

            // Generate button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: 0.6,
                  ),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome, color: Colors.white),
                label: Text(
                  _isGenerating ? 'Generating…' : 'Generate Diary',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required bool isDark,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        fontSize: 14,
      ),
      filled: true,
      fillColor: isDark
          ? AppColors.surfaceDarkElevated
          : AppColors.primary.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel({required this.text, required this.isDark});
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
      ),
    );
  }
}

// ── Voice Diary Bottom Sheet ──────────────────────────────────────────────────

class _VoiceDiarySheet extends StatefulWidget {
  const _VoiceDiarySheet();

  @override
  State<_VoiceDiarySheet> createState() => _VoiceDiarySheetState();
}

class _VoiceDiarySheetState extends State<_VoiceDiarySheet>
    with TickerProviderStateMixin {
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isRecording = false;
  bool _isProcessing = false;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final diaryDir = Directory('${dir.path}/diary_voice');
      if (!await diaryDir.exists()) await diaryDir.create(recursive: true);
      final path =
          '${diaryDir.path}/diary_${DateTime.now().millisecondsSinceEpoch}.m4a';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  Future<void> _stopAndCreate() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });
      if (path == null || !mounted) return;

      try {
        await FastApiService().postVoice('/api/diary/voice', File(path));
        if (!mounted) return;
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not create diary: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).viewInsets.bottom + 36,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Header
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  color: AppColors.accentPink,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice Diary',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Speak your memories — AI writes in English',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Pulsing mic button
          if (!_isProcessing)
            GestureDetector(
              onTap: _isRecording ? _stopAndCreate : _startRecording,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (_, _) {
                  final v = _isRecording ? _pulseController.value : 0.0;
                  return SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isRecording)
                          Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.accentPink.withValues(
                                alpha: 0.14 * (1 - v),
                              ),
                            ),
                          ),
                        Container(
                          width: 160 - v * 10,
                          height: 160 - v * 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (_isRecording
                                    ? AppColors.accentPink
                                    : AppColors.primary)
                                .withValues(alpha: 0.12),
                          ),
                        ),
                        Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _isRecording
                                  ? const [
                                      Color(0xFFFF7B95),
                                      AppColors.accentPink,
                                    ]
                                  : const [
                                      Color(0xFF7B5AFF),
                                      AppColors.primaryDark,
                                    ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isRecording
                                        ? AppColors.accentPink
                                        : AppColors.primary)
                                    .withValues(alpha: 0.40),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isRecording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          else ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'AI is composing your diary entry…',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            _isProcessing
                ? 'Analysing voice + tour reminders + weather…'
                : _isRecording
                    ? 'Tap to stop and create diary'
                    : 'Tap the mic to start speaking',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (!_isRecording && !_isProcessing) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.tips_and_updates_outlined,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Try: "Today I visited Skardu fort, the weather was amazing and we had a great time…"',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  const _DatePickerButton({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceDarkElevated
              : AppColors.primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
