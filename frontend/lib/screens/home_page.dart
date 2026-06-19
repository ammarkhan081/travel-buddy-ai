import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pakistan_destination.dart';
import '../models/travel_agency.dart';
import '../services/active_journey.dart';
import '../services/auth_service.dart';
import '../services/fastapi_service.dart';
import '../theme/app_colors.dart';
import '../utils/app_keys.dart';
import '../utils/date_utils.dart' as fyp_date;
import 'destination_detail_screen.dart';
import 'destination_list_screen.dart';
import 'modules/agency_list_bottom_sheet.dart';
import 'modules/profile_settings.dart';

/// Home / Dashboard.
///
/// Visually matches the purple-gradient "Ammar Khan" mockup but every section
/// is plain-and-safe: no slivers, no all-positioned Stacks, every Container
/// has an explicit width. Initial async work is deferred to the first
/// post-frame callback so initState never touches setState synchronously.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  // ── Services / state ──────────────────────────────────────────────────────
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FastApiService _api = FastApiService();
  final TextEditingController _searchController = TextEditingController();
  final PageController _heroPageController = PageController();

  // User
  String _userFirst = 'Hello';
  String _userLast = '';
  String _userName = 'Traveller';
  String _userEmail = '';
  String _userInitials = 'U';
  String? _profileImageUrl;

  // Dashboard data
  List<Map<String, dynamic>> _liveAlerts = const [];
  bool _isLoadingAlerts = true;
  bool _alertsJourneyActive = false;

  List<Map<String, dynamic>> _upcomingReminders = const [];
  int _bellCount = 0;
  bool _isLoadingReminders = true;

  // Filters
  String _searchQuery = '';
  String _activeCategory = 'All';
  int _selectedTabIndex = 0;

  // Hero carousel
  int _heroIndex = 0;
  Timer? _heroTimer;

  // Favorites
  final Set<String> _favoriteDestinationNames = <String>{};

  static const List<String> _heroDestinationNames = [
    'Kalam',
    'Skardu',
    'Murree',
    'Abbottabad',
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Defer all async work to after the first frame so setState calls inside
    // these futures never race with the initial build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadUserData();
      _loadFavoriteDestinations();
      _fetchUpcomingReminders();
      _fetchWeatherAndAlerts();
      _startHeroAutoSlide();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes so we know when the dashboard becomes visible
    // again after returning from another screen.
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  /// Called when a screen pushed on top of the dashboard is popped and the
  /// dashboard becomes visible again. Re-fetch journey-driven alerts so any
  /// destination change (start / change / clear journey) is reflected here.
  @override
  void didPopNext() {
    if (!mounted) return;
    _fetchWeatherAndAlerts();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _heroTimer?.cancel();
    _heroPageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startHeroAutoSlide() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted || !_heroPageController.hasClients) return;
      final next = (_heroIndex + 1) % _heroDestinationNames.length;
      _heroPageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  // ── User loading ──────────────────────────────────────────────────────────
  Future<void> _loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user == null) return;
      final fullName =
          user.displayName ?? user.email?.split('@').first ?? 'Traveller';
      final parts = fullName
          .trim()
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      final first = parts.isNotEmpty ? parts.first : fullName;
      final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      String? photoUrl;
      try {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          photoUrl = doc.data()?['profileImageUrl'] as String?;
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _userName = fullName;
        _userFirst = first;
        _userLast = last;
        _userEmail = user.email ?? '';
        _userInitials =
            (parts.isEmpty ? 'U' : parts.map((p) => p[0]).take(2).join())
                .toUpperCase();
        _profileImageUrl = photoUrl ?? user.photoURL;
      });
    } catch (e) {
      debugPrint('HomePage._loadUserData error: $e');
    }
  }

  String _favoriteStorageKey(String? uid) => uid == null || uid.isEmpty
      ? 'favorite_destinations_guest'
      : 'favorite_destinations_$uid';

  Future<void> _loadFavoriteDestinations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _authService.currentUser;
      final key = _favoriteStorageKey(user?.uid);
      final local = prefs.getStringList(key) ?? <String>[];
      if (!mounted) return;
      setState(() {
        _favoriteDestinationNames
          ..clear()
          ..addAll(local.toSet());
      });
    } catch (e) {
      debugPrint('HomePage._loadFavoriteDestinations error: $e');
    }
  }

  Future<void> _saveFavoriteDestinations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _authService.currentUser;
      final key = _favoriteStorageKey(user?.uid);
      final list = _favoriteDestinationNames.toList();
      await prefs.setStringList(key, list);
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'favoriteDestinations': list,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('HomePage._saveFavoriteDestinations error: $e');
    }
  }

  void _toggleFavorite(PakistanDestination d) {
    setState(() {
      if (_favoriteDestinationNames.contains(d.name)) {
        _favoriteDestinationNames.remove(d.name);
      } else {
        _favoriteDestinationNames.add(d.name);
      }
    });
    _saveFavoriteDestinations();
  }

  // ── Alerts ─────────────────────────────────────────────────────────────────
  Future<void> _fetchWeatherAndAlerts() async {
    if (!mounted) return;
    setState(() {
      _isLoadingAlerts = true;
    });
    try {
      final journey = await ActiveJourney.load();
      final bool journeyActive = journey != null;

      // Dashboard alerts are journey-driven: with no chosen destination there
      // is nothing to fetch — the card shows a "start a journey" prompt.
      if (!journeyActive) {
        if (!mounted) return;
        setState(() {
          _liveAlerts = const [];
          _alertsJourneyActive = false;
          _isLoadingAlerts = false;
        });
        return;
      }

      final label = journey.toName;

      Map<String, dynamic>? payload;
      try {
        final body = <String, dynamic>{
          'user_id': 'auth',
          'location': journey.toName,
          // Send GPS coords as origin when available so the traffic estimate
          // works (the label "Current Location" can't be geocoded).
          'origin': (journey.fromLat != null && journey.fromLon != null)
              ? '${journey.fromLat},${journey.fromLon}'
              : journey.fromName,
          'destination': journey.toName,
          'alert_types': const ['weather', 'traffic', 'news'],
        };
        final res = await _api.post(
          '/api/alerts/',
          body,
          timeout: const Duration(seconds: 30),
        );
        if (res is Map) payload = Map<String, dynamic>.from(res);
      } catch (e) {
        debugPrint('HomePage alerts POST failed: $e');
      }

      final alerts = <Map<String, dynamic>>[];
      if (payload != null) {
        if (payload['weather'] is Map) {
          final weather = Map<String, dynamic>.from(payload['weather'] as Map);
          alerts.add({
            'type': 'weather',
            'title': '${weather['condition'] ?? 'Weather'} · $label',
            'message': (weather['description'] ?? '').toString(),
            'severity': (weather['risk_level'] ?? 'low').toString(),
            'time': DateFormat('h:mm a').format(DateTime.now()),
          });
        }
        if (payload['traffic'] is Map) {
          final t = Map<String, dynamic>.from(payload['traffic'] as Map);
          final delay = t['estimated_delay'];
          if (delay is num && delay > 0) {
            alerts.add({
              'type': 'traffic',
              'title': 'Traffic on your route',
              'message': 'About $delay min delay on the way to $label.',
              'severity': (t['risk_level'] ?? 'medium').toString(),
              'time': DateFormat('h:mm a').format(DateTime.now()),
            });
          }
        }
        if (payload['news'] is Map) {
          final n = Map<String, dynamic>.from(payload['news'] as Map);
          final list = (n['headlines'] as List?) ?? const [];
          for (final h in list.take(2)) {
            alerts.add({
              'type': 'news',
              'title': 'News · $label',
              'message': h.toString(),
              'severity': (n['risk_level'] ?? 'low').toString(),
              'time': DateFormat('h:mm a').format(DateTime.now()),
            });
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _liveAlerts = alerts;
        _alertsJourneyActive = true;
        _isLoadingAlerts = false;
      });
    } catch (e) {
      debugPrint('HomePage._fetchWeatherAndAlerts error: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingAlerts = false;
      });
    }
  }

  Future<void> _fetchUpcomingReminders() async {
    if (!mounted) return;
    setState(() => _isLoadingReminders = true);
    try {
      final res = await _api.get('/api/reminders/');
      if (res is! List) {
        if (!mounted) return;
        setState(() {
          _upcomingReminders = const [];
          _bellCount = 0;
          _isLoadingReminders = false;
        });
        return;
      }
      final now = DateTime.now();
      final startOfTomorrow = DateTime(now.year, now.month, now.day + 1);
      final parsed = <Map<String, dynamic>>[];
      int bell = 0;
      for (final item in res) {
        if (item is! Map) continue;
        if ((item['status'] ?? 'pending').toString().toLowerCase() ==
            'completed') {
          continue;
        }
        final dt = fyp_date.DateUtils.parseToLocal(
          (item['datetime'] ?? '').toString(),
        );
        final overdue = dt.isBefore(now);
        final today = dt.isBefore(startOfTomorrow) && !overdue;
        if (overdue || today) bell++;
        parsed.add({
          ...Map<String, dynamic>.from(item),
          '_dt': dt,
          '_overdue': overdue,
          '_today': today,
        });
      }
      parsed.sort(
        (a, b) => (a['_dt'] as DateTime).compareTo(b['_dt'] as DateTime),
      );
      if (!mounted) return;
      setState(() {
        _upcomingReminders = parsed.take(6).toList();
        _bellCount = bell;
        _isLoadingReminders = false;
      });
    } catch (e) {
      debugPrint('HomePage._fetchUpcomingReminders error: $e');
      if (!mounted) return;
      setState(() {
        _upcomingReminders = const [];
        _bellCount = 0;
        _isLoadingReminders = false;
      });
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  Future<void> _openRoute(String route) async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (!mounted) return;
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    // Note: alerts/weather refresh is handled centrally by didPopNext (via
    // routeObserver) whenever the dashboard returns to the foreground, so we
    // only need to refresh reminders here.
    _fetchUpcomingReminders();
  }

  Future<void> _onNavTap(int index) async {
    if (!mounted) return;
    setState(() => _selectedTabIndex = index);
    switch (index) {
      case 0:
      case 1:
        return;
      case 2:
        await _openRoute('/chat');
        break;
      case 3:
        await _openRoute('/diary');
        break;
      case 4:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSettings()),
        );
        await _loadUserData();
        break;
    }
    if (!mounted) return;
    if (index >= 2) setState(() => _selectedTabIndex = 0);
  }

  // ── Filtering ─────────────────────────────────────────────────────────────
  Set<DestinationType>? _typesForCategory(String c) {
    switch (c) {
      case 'Nature':
        return {DestinationType.nature, DestinationType.mountain};
      case 'Culture':
        return {DestinationType.cultural, DestinationType.heritage};
      case 'Beaches':
        return {DestinationType.coastal};
      case 'Adventure':
        return {DestinationType.mountain, DestinationType.nature};
      case 'Food':
        return {DestinationType.urban, DestinationType.cultural};
      default:
        return null;
    }
  }

  List<PakistanDestination> _filteredTrending() {
    final types = _typesForCategory(_activeCategory);
    final q = _searchQuery.trim().toLowerCase();
    return trendingPakistanDestinations.where((d) {
      if (types != null && !types.contains(d.type)) return false;
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) ||
          d.province.toLowerCase().contains(q) ||
          d.typeLabel.toLowerCase().contains(q) ||
          d.summary.toLowerCase().contains(q) ||
          d.highlights.any((h) => h.toLowerCase().contains(q)) ||
          d.knownFor.toLowerCase().contains(q);
    }).toList();
  }

  PakistanDestination _byName(String name) =>
      trendingPakistanDestinations.firstWhere(
        (d) => d.name == name,
        orElse: () => trendingPakistanDestinations.first,
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
      drawer: _buildDrawer(),
      body: _selectedTabIndex == 1 ? _buildFavoritesBody() : _buildHomeBody(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHomeBody() {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadUserData(),
          _fetchUpcomingReminders(),
          _fetchWeatherAndAlerts(),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildHeroCarousel(),
          ),
          const SizedBox(height: 20),
          SizedBox(height: 92, child: _buildCategoryChips()),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildTrendingHeader(),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 230, child: _buildTrendingList()),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildDealsBanner(),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildWeatherAndAlerts(),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildUpcomingReminders(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Short dark band sits only behind the system status bar; the
          // gradient quickly fades into the scaffold background so the
          // header blends naturally with the rest of the body in BOTH light
          // and dark modes.
          stops: const [0.0, 0.12, 0.28, 1.0],
          colors: isDark
              ? const [
                  Color(0xFF050314), // very dark behind status bar
                  Color(0xFF1A1042), // transition
                  Color(0xFF2A1F55), // muted purple body
                  AppColors.bgDark, // matches dark scaffold
                ]
              : const [
                  Color(0xFF131434), // navy at very top
                  Color(0xFF4C3E8C), // brief transition
                  Color(0xFFE9E2FF), // soft lilac (header body)
                  AppColors.bgLight, // matches light scaffold
                ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      // Force light system icons (white) for the status bar over the dark top.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          bottom: false,
          child: Padding(
            // Extra vertical breathing room around the greeting + name.
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderRow(),
                const SizedBox(height: 22),
                _buildSearchBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Row(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          elevation: 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: SizedBox(
              width: 46,
              height: 46,
              child: Icon(
                Icons.menu_rounded,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                size: 22,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Builder(
            builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_greeting()} 👋',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        height: 1.15,
                      ),
                      children: [
                        TextSpan(text: _userFirst),
                        if (_userLast.isNotEmpty) const TextSpan(text: ' '),
                        if (_userLast.isNotEmpty)
                          TextSpan(
                            text: _userLast,
                            style: const TextStyle(color: AppColors.primary),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your smart travel & lifestyle companion',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        _BellWithBadge(count: _bellCount, onTap: _openNotificationsPanel),
        const SizedBox(width: 10),
        _buildAvatar(),
      ],
    );
  }

  Widget _buildAvatar() {
    return InkWell(
      borderRadius: BorderRadius.circular(23),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSettings()),
        );
        await _loadUserData();
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF6F4CFF), width: 2),
        ),
        child: ClipOval(
          child: (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
              ? Image.network(
                  _profileImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _avatarFallback(),
                )
              : _avatarFallback(),
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: const Color(0xFF6F4CFF),
      alignment: Alignment.center,
      child: Text(
        _userInitials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }

  /// Time-neutral greeting — works at any hour, so the user never sees
  /// "Good Morning" at 11 PM.
  String _greeting() => 'Welcome back,';

  // ── Search bar ────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search destinations, experiences...',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey.shade600,
                  size: 22,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          shadowColor: const Color(0xFF6F4CFF).withValues(alpha: 0.4),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openFilterSheet,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF7B5AFF), Color(0xFF4F2BFF)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero carousel ─────────────────────────────────────────────────────────
  Widget _buildHeroCarousel() {
    return SizedBox(
      width: double.infinity,
      height: 320,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: PageView.builder(
                controller: _heroPageController,
                onPageChanged: (i) {
                  if (mounted) setState(() => _heroIndex = i);
                },
                itemCount: _heroDestinationNames.length,
                itemBuilder: (_, i) {
                  final dest = _byName(_heroDestinationNames[i]);
                  return _HeroSlide(
                    destination: dest,
                    isFavorite: _favoriteDestinationNames.contains(dest.name),
                    onFavorite: () => _toggleFavorite(dest),
                    onStartJourney: () => _openRoute('/startJourney'),
                    onOpen: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DestinationDetailScreen(destination: dest),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_heroDestinationNames.length, (i) {
                final active = i == _heroIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: active ? 18 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF7B5AFF)
                        : Colors.white.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Category chips ────────────────────────────────────────────────────────
  Widget _buildCategoryChips() {
    const categories = [
      ('All', Icons.grid_view_rounded, Color(0xFF7B5AFF)),
      ('Nature', Icons.terrain, Color(0xFF34C77B)),
      ('Culture', Icons.account_balance, Color(0xFFE89B2C)),
      ('Beaches', Icons.beach_access, Color(0xFF20B2C9)),
      ('Adventure', Icons.travel_explore, Color(0xFFE94E66)),
      ('Food', Icons.restaurant, Color(0xFFE67934)),
      ('More', Icons.apps_rounded, Color(0xFF6F4CFF)),
    ];
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (_, i) {
        final (label, icon, color) = categories[i];
        final active = _activeCategory == label;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return Material(
          color: active
              ? color.withValues(alpha: isDark ? 0.20 : 0.12)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _activeCategory = label),
            child: Container(
              width: 76,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? color.withValues(alpha: 0.5)
                      : Colors.transparent,
                  width: 1.4,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                      color: active
                          ? color
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
      },
    );
  }

  // ── Trending Destinations ────────────────────────────────────────────────
  Widget _buildTrendingHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        const Icon(Icons.auto_awesome, color: AppColors.primaryLight, size: 20),
        const SizedBox(width: 6),
        Text(
          'Trending Destinations',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final list = _filteredTrending();
            if (list.isEmpty) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DestinationListScreen(
                  title: _activeCategory == 'All'
                      ? 'Trending Destinations'
                      : '$_activeCategory Destinations',
                  destinations: list,
                ),
              ),
            );
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                Text(
                  'See All',
                  style: TextStyle(
                    color: Color(0xFF6F4CFF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: Color(0xFF6F4CFF)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendingList() {
    final list = _filteredTrending();
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _emptyCard(
          'No destinations match',
          'Try a different category or search.',
        ),
      );
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(width: 12),
      itemBuilder: (_, i) {
        final d = list[i];
        return _TrendingCard(
          destination: d,
          isFavorite: _favoriteDestinationNames.contains(d.name),
          onFavorite: () => _toggleFavorite(d),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DestinationDetailScreen(destination: d),
              ),
            );
          },
        );
      },
    );
  }

  // ── Deals banner ──────────────────────────────────────────────────────────
  Widget _buildDealsBanner() {
    return Material(
      borderRadius: BorderRadius.circular(22),
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: _openAgenciesSheet,
        child: Container(
          width: double.infinity,
          height: 140,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF6F4CFF), // deep purple
                Color(0xFF8E5DFF), // violet
                Color(0xFFB35FE0), // magenta
                Color(0xFFE36DC4), // pink
              ],
              stops: [0.0, 0.45, 0.78, 1.0],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6F4CFF).withValues(alpha: 0.40),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Plane silhouette top-right
              const Positioned(
                top: 14,
                right: 18,
                child: Icon(Icons.flight, color: Colors.white, size: 22),
              ),
              // Dotted curved flight path — starts from the camera/suitcase
              // area at bottom-left and arcs across the banner up to the
              // airplane in the top-right corner.
              Positioned(
                left: 372,
                top: 34,
                right: 74,
                bottom: 34,
                child: CustomPaint(painter: _DottedTrailPainter()),
              ),
              // Travel illustration cluster (luggage + hat + camera + leaves)
              const Positioned(
                left: 14,
                top: 14,
                bottom: 14,
                child: _DealsIllustration(),
              ),
              // Text + CTA
              Padding(
                padding: const EdgeInsets.fromLTRB(118, 18, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exclusive Deals',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Up to 30% OFF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'On selected destinations',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Explore Deals',
                            style: TextStyle(
                              color: Color(0xFF6F4CFF),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward,
                            color: Color(0xFF6F4CFF),
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAgenciesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.78,
        child: AgencyListBottomSheet(agencies: TravelAgency.mockAgencies),
      ),
    );
  }

  // ── Weather + Alerts ─────────────────────────────────────────────────────
  Widget _buildWeatherAndAlerts() {
    // Weather card removed: weather is now shown per-destination inside the
    // Alerts screen. The dashboard shows only the Active Alerts card full width.
    return SizedBox(
      height: 180,
      child: _buildAlertsCard(),
    );
  }

  Widget _buildAlertsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const []
            : AppShadows.softCard,
      ),
      child: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: AppColors.primaryLight,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Active Alerts',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _openRoute('/alerts'),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Text(
                          'See All',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isLoadingAlerts)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (!_alertsJourneyActive)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Start a journey to see destination alerts.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (_liveAlerts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No active alerts for now.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  _buildAlertsSummary(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAlertsSummary() {
    final a = _liveAlerts.first;
    final color = _severityColor((a['severity'] ?? 'low').toString());
    final icon = _typeIcon((a['type'] ?? 'info').toString());
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (a['title'] ?? '').toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                (a['time'] ?? '').toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE8FCF1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Live',
            style: TextStyle(
              color: Color(0xFF1F9B62),
              fontWeight: FontWeight.w800,
              fontSize: 9.5,
            ),
          ),
        ),
      ],
    );
  }

  Color _severityColor(String s) {
    switch (s) {
      case 'critical':
      case 'high':
        return const Color(0xFFE94E66);
      case 'medium':
        return const Color(0xFFE89B2C);
      default:
        return const Color(0xFF34C77B);
    }
  }

  IconData _typeIcon(String t) {
    switch (t) {
      case 'weather':
        return Icons.cloud_outlined;
      case 'traffic':
        return Icons.traffic;
      case 'news':
        return Icons.article_outlined;
      default:
        return Icons.info_outline;
    }
  }

  // ── Upcoming reminders ────────────────────────────────────────────────────
  Widget _buildUpcomingReminders() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Upcoming Reminders',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _openRoute('/reminders'),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Row(
                  children: [
                    Text(
                      'See All',
                      style: TextStyle(
                        color: Color(0xFF6F4CFF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Color(0xFF6F4CFF),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoadingReminders)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_upcomingReminders.isEmpty)
          _emptyCard(
            'No upcoming reminders',
            'Add one from the Reminders module.',
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _upcomingReminders.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final r = _upcomingReminders[i];
                return _ReminderCard(
                  title: (r['title'] ?? 'Reminder').toString(),
                  dt: r['_dt'] as DateTime,
                  isOverdue: r['_overdue'] == true,
                  onTap: () => _openRoute('/reminders'),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _emptyCard(String title, String subtitle) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(0, Icons.home, Icons.home_outlined, 'Home'),
              _navItem(1, Icons.favorite, Icons.favorite_border, 'Favorites'),
              _navItem(2, Icons.chat_bubble, Icons.chat_bubble_outline, 'Chat'),
              _navItem(3, Icons.menu_book, Icons.menu_book_outlined, 'Diary'),
              _navItem(4, Icons.person, Icons.person_outline, 'Account'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData filled, IconData outline, String label) {
    final active = _selectedTabIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        onTap: () => _onNavTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? filled : outline,
              color: active
                  ? AppColors.primary
                  : (isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiary),
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? AppColors.primary
                    : (isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary),
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Favorites view ────────────────────────────────────────────────────────
  Widget _buildFavoritesBody() {
    final all = <PakistanDestination>[
      ...trendingPakistanDestinations,
      ...topPickPakistanDestinations,
    ];
    final uniq = <String, PakistanDestination>{};
    for (final d in all) {
      uniq.putIfAbsent(d.name, () => d);
    }
    final favs = uniq.values
        .where((d) => _favoriteDestinationNames.contains(d.name))
        .toList();

    if (favs.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.favorite_border,
                  size: 60,
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  'No favorite places yet',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap the heart on any destination to add it here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: favs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final d = favs[i];
          return SizedBox(
            height: 200,
            child: _TrendingCard(
              destination: d,
              isFavorite: true,
              onFavorite: () => _toggleFavorite(d),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DestinationDetailScreen(destination: d),
                  ),
                );
              },
              expandWidth: true,
            ),
          );
        },
      ),
    );
  }

  // ── Drawer ────────────────────────────────────────────────────────────────
  Drawer _buildDrawer() {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF40345E), Color(0xFF362173)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileSettings(),
                          ),
                        );
                        await _loadUserData();
                      },
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child:
                              (_profileImageUrl != null &&
                                  _profileImageUrl!.isNotEmpty)
                              ? Image.network(
                                  _profileImageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Center(
                                    child: Text(
                                      _userInitials,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                                )
                              : Center(
                                  child: Text(
                                    _userInitials,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _userName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _userEmail,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _drawerTile(
                      Icons.home_rounded,
                      'Home',
                      () => Navigator.pop(context),
                    ),
                    _drawerTile(
                      Icons.chat_bubble_outline,
                      'Chat',
                      () => _openRoute('/chat'),
                    ),
                    _drawerTile(
                      Icons.notifications_active,
                      'Alerts',
                      () => _openRoute('/alerts'),
                    ),
                    _drawerTile(
                      Icons.alarm,
                      'Reminders',
                      () => _openRoute('/reminders'),
                    ),
                    _drawerTile(
                      Icons.book,
                      'Diary',
                      () => _openRoute('/diary'),
                    ),
                    _drawerTile(
                      Icons.mic,
                      'Voice Notes',
                      () => _openRoute('/voiceNotes'),
                    ),
                    _drawerTile(
                      Icons.account_balance_wallet,
                      'Expenses',
                      () => _openRoute('/expenseTracker'),
                    ),
                    _drawerTile(
                      Icons.map_outlined,
                      'Journey History',
                      () => _openRoute('/journeyHistory'),
                    ),
                    _drawerTile(
                      Icons.emergency_share_outlined,
                      'Emergency Contacts',
                      () => _openRoute('/emergencyContacts'),
                    ),
                    _drawerTile(
                      Icons.luggage_rounded,
                      'Packing Checklist',
                      () => _openRoute('/packingChecklist'),
                    ),
                    _drawerTile(
                      Icons.currency_exchange_rounded,
                      'Currency Converter',
                      () => _openRoute('/currencyConverter'),
                    ),
                    const SizedBox(height: 12),
                    _drawerTile(
                      Icons.feedback,
                      'Feedback',
                      () => _openRoute('/feedback'),
                    ),
                    _drawerTile(Icons.logout, 'Logout', () async {
                      await _authService.signOut();
                      if (!mounted) return;
                      Navigator.pushReplacementNamed(context, '/login');
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Notifications panel ───────────────────────────────────────────────────
  void _openNotificationsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Notifications',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _bellCount > 0 ? '$_bellCount due' : 'All clear',
                        style: TextStyle(
                          color: _bellCount > 0
                              ? AppColors.danger
                              : AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: _upcomingReminders.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.notifications_off,
                                  size: 54,
                                  color: isDark
                                      ? AppColors.textTertiaryDark
                                      : AppColors.textTertiary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  "You're all caught up",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: isDark
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.all(16),
                          itemCount: _upcomingReminders.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final r = _upcomingReminders[i];
                            final overdue = r['_overdue'] == true;
                            final dt = r['_dt'] as DateTime;
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color:
                                    (overdue
                                            ? AppColors.danger
                                            : AppColors.primary)
                                        .withValues(
                                          alpha: isDark ? 0.16 : 0.08,
                                        ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: overdue
                                          ? AppColors.danger
                                          : AppColors.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.alarm,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (r['title'] ?? 'Reminder').toString(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                            color: isDark
                                                ? AppColors.textPrimaryDark
                                                : AppColors.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat(
                                            'EEE, d MMM • h:mm a',
                                          ).format(dt),
                                          style: TextStyle(
                                            color: isDark
                                                ? AppColors.textSecondaryDark
                                                : AppColors.textSecondary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: overdue
                                          ? AppColors.danger
                                          : AppColors.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      overdue ? 'Overdue' : 'Today',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openRoute('/reminders');
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Open Reminders'),
                      ),
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

  // ── Filter sheet ──────────────────────────────────────────────────────────
  void _openFilterSheet() {
    final categories = const [
      'All',
      'Nature',
      'Culture',
      'Beaches',
      'Adventure',
      'Food',
      'More',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String tempCat = _activeCategory;
        RangeValues priceRange = const RangeValues(4000, 16000);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final theme = Theme.of(ctx);
            final isDark = theme.brightness == Brightness.dark;
            final mutedText = isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary;
            final headingText = isDark
                ? AppColors.textPrimaryDark
                : AppColors.textPrimary;
            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  Text(
                    'Filter destinations',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: headingText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Category',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: headingText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((c) {
                      final active = tempCat == c;
                      return ChoiceChip(
                        label: Text(c),
                        selected: active,
                        onSelected: (_) => setSheet(() => tempCat = c),
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.15,
                        ),
                        labelStyle: TextStyle(
                          color: active ? AppColors.primary : headingText,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Price per day (PKR)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: headingText,
                    ),
                  ),
                  RangeSlider(
                    values: priceRange,
                    min: 4000,
                    max: 16000,
                    divisions: 12,
                    activeColor: AppColors.primary,
                    labels: RangeLabels(
                      'PKR ${(priceRange.start / 1000).round()}k',
                      'PKR ${(priceRange.end / 1000).round()}k',
                    ),
                    onChanged: (v) => setSheet(() => priceRange = v),
                  ),
                  Text(
                    'Showing PKR ${(priceRange.start / 1000).round()}k – PKR ${(priceRange.end / 1000).round()}k/day',
                    style: TextStyle(color: mutedText, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() => _activeCategory = 'All');
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() => _activeCategory = tempCat);
                            final filtered = trendingPakistanDestinations.where(
                              (d) {
                                final types = _typesForCategory(tempCat);
                                if (types != null && !types.contains(d.type)) {
                                  return false;
                                }
                                return d.pricePerDay >= priceRange.start &&
                                    d.pricePerDay <= priceRange.end;
                              },
                            ).toList();
                            if (filtered.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DestinationListScreen(
                                    title: 'Filtered Destinations',
                                    destinations: filtered,
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Reusable sub-widgets
// ───────────────────────────────────────────────────────────────────────────

class _BellWithBadge extends StatelessWidget {
  const _BellWithBadge({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  size: 22,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({
    required this.destination,
    required this.isFavorite,
    required this.onFavorite,
    required this.onStartJourney,
    required this.onOpen,
  });

  final PakistanDestination destination;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onStartJourney;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            destination.assetImagePath,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(color: Colors.grey.shade300),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: GestureDetector(
              onTap: onFavorite,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: const Color(0xFFE94E66),
                  size: 20,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 38),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TIME TO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Explore',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      destination.name,
                      style: const TextStyle(
                        color: Color(0xFFFF9BCB),
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      destination.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(40),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(40),
                        onTap: onStartJourney,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Start Journey',
                                style: TextStyle(
                                  color: Color(0xFF11102A),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 30,
                                height: 30,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF6F4CFF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_forward,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  const _TrendingCard({
    required this.destination,
    required this.isFavorite,
    required this.onFavorite,
    required this.onTap,
    this.expandWidth = false,
  });

  final PakistanDestination destination;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onTap;
  final bool expandWidth;

  Color _discountColor() {
    if (destination.discount >= 18) return const Color(0xFF34C77B);
    if (destination.discount >= 13) return const Color(0xFFFF7AAB);
    if (destination.discount >= 9) return const Color(0xFF8E5DFF);
    return const Color(0xFFFFA64A);
  }

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              destination.assetImagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(color: Colors.grey.shade300),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _discountColor(),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${destination.discount}% OFF',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: GestureDetector(
                onTap: onFavorite,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: const Color(0xFFE94E66),
                    size: 16,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    destination.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 12,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          destination.province,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.star,
                        size: 12,
                        color: Color(0xFFFFC93B),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        destination.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return SizedBox(width: expandWidth ? double.infinity : 200, child: card);
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.title,
    required this.dt,
    required this.isOverdue,
    required this.onTap,
  });

  final String title;
  final DateTime dt;
  final bool isOverdue;
  final VoidCallback onTap;

  IconData _pickIcon() {
    final t = title.toLowerCase();
    if (t.contains('flight') || t.contains('plane')) return Icons.flight;
    if (t.contains('hotel') ||
        t.contains('check-in') ||
        t.contains('checkin')) {
      return Icons.apartment;
    }
    if (t.contains('food') || t.contains('lunch') || t.contains('dinner')) {
      return Icons.restaurant;
    }
    return Icons.alarm;
  }

  Color _bg() => isOverdue ? const Color(0xFFFFEDEF) : const Color(0xFFEDF2FF);
  Color _accent() =>
      isOverdue ? const Color(0xFFE94E66) : const Color(0xFF4F7AFF);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _bg(),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 210,
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _accent().withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_pickIcon(), color: _accent(), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF11102A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM d, h:mm a').format(dt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6B6480),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _accent(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isOverdue ? 'Overdue' : 'Upcoming',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cluster illustration for the "Exclusive Deals" banner — a yellow suitcase
/// with a brown fedora sitting on top, a small camera at its feet, and a leaf
/// sprig peeking out behind. Pure-Flutter (no asset), so it works offline.
/// Premium travel illustration for the Exclusive Deals banner.
///
/// Composition (back to front):
///   1. A soft white glowing ellipse acting as a "platform" under the cluster
///   2. Three tropical leaves peeking out behind everything
///   3. A yellow→orange luxury suitcase with chrome handle, latch band,
///      corner studs and a glossy light reflection
///   4. A beige fedora hat sitting just to the right of the suitcase
///   5. A vintage black camera with chrome lens & flash in front of it
class _DealsIllustration extends StatelessWidget {
  const _DealsIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1) Glowing platform halo at the base of the cluster
          Positioned(
            left: -8,
            right: -8,
            bottom: -4,
            child: Container(
              height: 26,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
                borderRadius: BorderRadius.circular(60),
              ),
            ),
          ),

          // 2) Tropical leaves (back layer) — three small leaves on the LEFT
          // matching the mockup: one peeking above the suitcase top, one
          // sticking out mid-left, one smaller leaf at the bottom near the
          // camera. All point outward to the left so the cluster reads as a
          // compact stack with greenery escaping from behind it.
          // Top-left leaf — above the suitcase handle area
          Positioned(
            left: 8,
            top: 16,
            child: Transform.rotate(
              angle: -0.75, // ~ -43°, pointing up-left
              child: const Icon(Icons.eco, color: Color(0xFF6BD18A), size: 20),
            ),
          ),
          // Mid-left leaf — biggest, sticks out from behind the suitcase
          Positioned(
            left: -2,
            top: 62,
            child: Transform.rotate(
              angle: -1.3, // ~ -75°, pointing left horizontally
              child: const Icon(Icons.eco, color: Color(0xFF4FBF7A), size: 23),
            ),
          ),
          // Bottom-left leaf — small, next to the camera
          Positioned(
            left: 6,
            bottom: 18,
            child: Transform.rotate(
              angle: -0.95, // ~ -55°, pointing down-left
              child: const Icon(Icons.eco, color: Color(0xFF55C685), size: 14),
            ),
          ),

          // 3) Yellow→orange luxury suitcase
          Positioned(
            left: 20,
            top: 22,
            child: Container(
              width: 62,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFE166), // bright yellow highlight
                    Color(0xFFFFB02E), // warm orange-yellow body
                    Color(0xFFE89327), // deeper orange shade
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(2, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Handle slot at top
                  Positioned(
                    top: 8,
                    left: 14,
                    right: 14,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Chrome middle band (latch)
                  Positioned(
                    top: 36,
                    left: 4,
                    right: 4,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.32),
                            Colors.black.withValues(alpha: 0.20),
                            Colors.black.withValues(alpha: 0.32),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Two small clasp dots on the latch
                  Positioned(top: 37, left: 14, child: _clasp()),
                  Positioned(top: 37, right: 14, child: _clasp()),
                  // Bottom-corner studs
                  Positioned(left: 6, bottom: 6, child: _stud()),
                  Positioned(right: 6, bottom: 6, child: _stud()),
                  // Glossy light reflection on the front face
                  Positioned(
                    left: 6,
                    top: 4,
                    child: Container(
                      width: 16,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.4),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Suitcase chrome handle
          Positioned(
            left: 35,
            top: 12,
            child: Container(
              width: 32,
              height: 16,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF8A5722), width: 2.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
              ),
            ),
          ),

          // 4) Beige fedora hat — sits to the right of the suitcase
          Positioned(
            right: -4,
            bottom: 18,
            child: SizedBox(
              width: 54,
              height: 30,
              child: Stack(
                children: [
                  // Hat brim
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFE0BE85), Color(0xFFA88456)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 7,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Hat crown
                  Positioned(
                    bottom: 7,
                    left: 14,
                    child: Container(
                      width: 26,
                      height: 22,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFE9C68F), Color(0xFFB89265)],
                        ),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(13),
                        ),
                      ),
                    ),
                  ),
                  // Hatband
                  Positioned(
                    bottom: 8,
                    left: 14,
                    child: Container(
                      width: 26,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B4421),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5) Vintage black camera — sits IN FRONT of the suitcase, slightly
          // overlapping its lower-front edge. Tilted a touch for a natural,
          // 3D-product-shot feel that matches the mockup.
          Positioned(
            left: 18,
            bottom: 4,
            child: Transform.rotate(
              angle: -0.08, // tiny tilt left for that "placed casually" look
              child: SizedBox(
                width: 38,
                height: 28,
                child: Stack(
                  children: [
                    // Camera body
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF2D2D3A), Color(0xFF0E0E1A)],
                        ),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 6,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                    // Top viewfinder bump
                    Positioned(
                      top: -3,
                      left: 12,
                      child: Container(
                        width: 10,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A24),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    // Chrome lens
                    Positioned(
                      left: 8,
                      top: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [
                              Color(0xFFB9D2FF),
                              Color(0xFF4F7AFF),
                              Color(0xFF1B2A6B),
                            ],
                            stops: [0.0, 0.55, 1.0],
                          ),
                          border: Border.all(
                            color: const Color(0xFF6B7888),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        // Tiny white highlight on the lens
                        child: Stack(
                          children: [
                            Positioned(
                              top: 2,
                              left: 3,
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Flash dot
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        width: 3.5,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD25C),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFFFD25C,
                              ).withValues(alpha: 0.7),
                              blurRadius: 3,
                            ),
                          ],
                        ),
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

  Widget _stud() => Container(
    width: 4.5,
    height: 4.5,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      shape: BoxShape.circle,
    ),
  );

  Widget _clasp() => Container(
    width: 3.5,
    height: 3.5,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      shape: BoxShape.circle,
    ),
  );
}

/// Dashed curved trail that arcs from the suitcase to the airplane on the
/// Exclusive Deals banner.
class _DottedTrailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Keep the trail in the empty right side of the banner: it starts low,
    // sweeps upward, and finishes beside the airplane without crossing text.
    final path = Path()
      ..moveTo(0, size.height * 0.98)
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.38,
        size.width * 0.48,
        size.height * 0.05,
        size.width,
        size.height * 0.16,
      );

    const dashWidth = 6.0;
    const dashSpace = 6.0;
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double dist = 0;
      while (dist < metric.length) {
        final double next = (dist + dashWidth)
            .clamp(0.0, metric.length)
            .toDouble();
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedTrailPainter oldDelegate) => false;
}
