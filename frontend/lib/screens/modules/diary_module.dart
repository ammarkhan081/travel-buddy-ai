import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'edit_diary_entry.dart';
import '../../services/fastapi_service.dart';
import '../../services/api_exceptions.dart';
import '../../utils/ui_utils.dart';

class DiaryModule extends StatefulWidget {
  const DiaryModule({super.key});

  @override
  State<DiaryModule> createState() => _DiaryModuleState();
}

class _DiaryModuleState extends State<DiaryModule> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isGenerating = false;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDate;
  List<dynamic> _allEntries = [];
  List<dynamic> _filteredEntries = [];

  Future<List<dynamic>>? _diaryFuture;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterEntries);
    _fetchDiary();
  }

  void _fetchDiary() {
    setState(() {
      _diaryFuture = FastApiService().get('/api/diary/').then((res) {
        final entries = res as List<dynamic>;
        _allEntries = entries.toList()
          ..sort((a, b) {
            final aTime = DateTime.tryParse(a['timestamp'] ?? '');
            final bTime = DateTime.tryParse(b['timestamp'] ?? '');
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });
        _filteredEntries = _allEntries;
        return _allEntries;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterEntries() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEntries = _allEntries.where((entry) {
        final title = (entry['title'] ?? '').toLowerCase();
        final content = (entry['content'] ?? '').toLowerCase();
        final matchesQuery = title.contains(query) || content.contains(query);

        if (_selectedDate != null) {
          final entryDate = DateTime.tryParse(entry['timestamp'] ?? '');
          if (entryDate == null) return false;
          final entryDateOnly = DateTime(entryDate.year, entryDate.month, entryDate.day);
          final selectedDateOnly = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
          return matchesQuery && entryDateOnly.isAtSameMomentAs(selectedDateOnly);
        }

        return matchesQuery;
      }).toList();
    });
  }

  Future<Position?> _fetchLocationSafely() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _filterEntries();
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedDate = null;
      _searchController.clear();
      _filteredEntries = _allEntries;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _auth.currentUser;
    
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              const Text('Please log in to view diary entries', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200.0,
              floating: false,
              pinned: true,
              stretch: true,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [
                  StretchMode.zoomBackground,
                  StretchMode.blurBackground,
                  StretchMode.fadeTitle,
                ],
                centerTitle: true,
                title: Text(
                  'My Diary',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                        theme.colorScheme.tertiaryContainer,
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -50,
                        top: -20,
                        child: Icon(
                          Icons.auto_stories,
                          size: 200,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 20),
                              Text(
                                'Capture your thoughts,',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary.withOpacity(0.8),
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                'Create your legacy.',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () => _selectDate(context),
                ),
                if (_selectedDate != null || _searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.filter_list_off),
                    onPressed: _clearFilters,
                  ),
              ],
            ),
          ];
        },
        body: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search your memories...',
                      prefixIcon: const Icon(Icons.search),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              if (_selectedDate != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Chip(
                        avatar: const Icon(Icons.event, size: 16),
                        label: Text(DateFormat('MMM dd, yyyy').format(_selectedDate!)),
                        onDeleted: () {
                          setState(() {
                            _selectedDate = null;
                            _filterEntries();
                          });
                        },
                        backgroundColor: theme.colorScheme.primaryContainer,
                        labelStyle: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                        deleteIconColor: theme.colorScheme.onPrimaryContainer,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      _buildAiGenerationCard(theme),

                      FutureBuilder<List<dynamic>>(
                        future: _diaryFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting && _allEntries.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(40.0),
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return _buildErrorState(theme, snapshot.error);
                          }

                          if (_allEntries.isEmpty) {
                            return _buildEmptyState(theme);
                          }

                          if (_filteredEntries.isEmpty && _searchController.text.isNotEmpty) {
                            return _buildNoResultsState(theme);
                          }

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            itemCount: _filteredEntries.length,
                            itemBuilder: (context, index) {
                              final data = _filteredEntries[index];
                              return _buildDiaryEntryCard(context, data['id'].toString(), data);
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EditDiaryEntry(),
            ),
          );
          if (result == true) {
            _fetchDiary();
          }
        },
        icon: const Icon(Icons.edit_note),
        label: const Text('New Entry'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        elevation: 4,
      ),
    );
  }

  Widget _buildAiGenerationCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.secondaryContainer,
            theme.colorScheme.tertiaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                Icons.auto_awesome,
                size: 100,
                color: theme.colorScheme.primary.withOpacity(0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.psychology, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Magic Entry',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                            Text(
                              'Summarize your day automatically',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSecondaryContainer.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isGenerating ? null : _generateAiDiary,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 0,
                      ),
                      child: _isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.auto_awesome, size: 18),
                                SizedBox(width: 8),
                                Text('Generate Summary', style: TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaryEntryCard(BuildContext context, String docId, Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final title = data['title'] ?? 'Untitled';
    final content = data['content'] ?? '';
    final createdAt = DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now();
    final isAiGenerated = data['type'] == 'ai' || (data['title']?.toString().contains('AI Summary') ?? false);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditDiaryEntry(entryId: docId, initialData: data),
            ),
          );
          if (result == true) {
            _fetchDiary();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isAiGenerated 
                          ? theme.colorScheme.tertiaryContainer 
                          : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isAiGenerated ? Icons.auto_awesome : Icons.edit_note,
                      color: isAiGenerated 
                          ? theme.colorScheme.onTertiaryContainer 
                          : theme.colorScheme.onPrimaryContainer,
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
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          DateFormat('EEEE, MMM dd • hh:mm a').format(createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurfaceVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20),
                            SizedBox(width: 12),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: theme.colorScheme.error),
                            const SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditDiaryEntry(entryId: docId, initialData: data),
                          ),
                        );
                        if (result == true) {
                          _fetchDiary();
                        }
                      } else if (value == 'delete') {
                        await _deleteEntry(docId);
                      }
                    },
                  ),
                ],
              ),
              if (content.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              
              // Image Thumbnail
              if (data['imageUrl'] != null) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    data['imageUrl'],
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 100,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Icon(Icons.broken_image_outlined, color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 12),
              Row(
                children: [
                  if (isAiGenerated)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'AI SUMMARY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.auto_stories, size: 100, color: theme.colorScheme.primary.withOpacity(0.2)),
          const SizedBox(height: 20),
          Text(
            'Your story begins here',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Keep a record of your journey, thoughts, and memories.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EditDiaryEntry()),
              );
              if (result == true) _fetchDiary();
            },
            icon: const Icon(Icons.add),
            label: const Text('Write First Entry'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 60, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          const Text('No entries match your search', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, Object? error) {
    String message = 'Failed to load entries';
    if (error is ApiResponseException) {
      message = error.message;
    }

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 60, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _fetchDiary(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEntry(String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry'),
        content: const Text('Are you sure you want to delete this diary entry? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FastApiService().delete('/api/diary/$docId');
        if (mounted) {
          UIFeedback.showSnackBar(context, 'Diary entry deleted');
          _fetchDiary();
        }
      } catch (e) {
        if (mounted) {
          UIFeedback.showSnackBar(context, 'Error deleting entry: $e', isError: true);
        }
      }
    }
  }

  Future<void> _generateAiDiary() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      _isGenerating = true;
    });

    try {
      final position = await _fetchLocationSafely();

      final apiService = FastApiService();
      final Map<String, dynamic> payload = {
        'user_id': user.uid,
        'days': 1,
      };
      if (position != null) {
        payload['latitude'] = position.latitude;
        payload['longitude'] = position.longitude;
      }

      await apiService.post('/api/diary/auto-generate', payload);

      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        UIFeedback.showSnackBar(context, 'AI Diary Entry generated and saved!');
        _fetchDiary();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        UIFeedback.showSnackBar(context, 'AI Generation failed: $e. Try adding some reminders or expenses first!', isError: true);
      }
    }
  }
}
