import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/fastapi_service.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import '../models/pakistan_destination.dart';
import '../models/travel_agency.dart';
import '../utils/date_utils.dart' as fyp_date;
import '../widgets/destination_image.dart';
import 'destination_detail_screen.dart';
import 'destination_list_screen.dart';
import 'modules/profile_settings.dart';
import 'modules/agency_list_bottom_sheet.dart';

enum _DestinationCardStyle { featured, compact }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _userName = 'User';
  String _userEmail = '';
  String _userInitials = 'U';
  
  // Dashboard data
  List<Map<String, dynamic>> _liveAlerts = [];
  bool _isLoadingAlerts = true;
  int _selectedTabIndex = 0;
  final Set<String> _favoriteDestinationNames = <String>{};

  OverlayEntry? _overlayEntry;
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadFavoriteDestinations();
    _fetchLiveAlerts();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    final user = _authService.currentUser;
    if (user != null) {
      setState(() {
        _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
        _userEmail = user.email ?? '';
        _userInitials = _userName.isNotEmpty
            ? _userName.split(' ').map((n) => n[0]).take(2).join().toUpperCase()
            : 'U';
      });
    }
  }

  Future<void> _loadFavoriteDestinations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _authService.currentUser;
      final favoriteKey = _favoriteStorageKey(user?.uid);
      final localFavorites = prefs.getStringList(favoriteKey) ?? <String>[];
      List<String> finalFavorites = localFavorites;

      if (user != null) {
        try {
          final userDoc = await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists) {
            final cloudFavorites = (userDoc.data()?['favoriteDestinations'] as List<dynamic>?)
                    ?.map((item) => item.toString())
                    .toList() ??
                <String>[];
            if (cloudFavorites.isNotEmpty) {
              finalFavorites = cloudFavorites;
              await prefs.setStringList(favoriteKey, cloudFavorites);
            } else if (localFavorites.isNotEmpty) {
              await _firestore.collection('users').doc(user.uid).set({
                'favoriteDestinations': localFavorites,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          } else if (localFavorites.isNotEmpty) {
            await _firestore.collection('users').doc(user.uid).set({
              'uid': user.uid,
              'favoriteDestinations': localFavorites,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } catch (_) {}
      }

      finalFavorites = finalFavorites.toSet().toList();
      if (!mounted) return;
      setState(() {
        _favoriteDestinationNames
          ..clear()
          ..addAll(finalFavorites);
      });
    } catch (_) {}
  }

  String _favoriteStorageKey(String? uid) {
    if (uid == null || uid.isEmpty) {
      return 'favorite_destinations_guest';
    }
    return 'favorite_destinations_$uid';
  }

  Future<void> _saveFavoriteDestinations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _authService.currentUser;
      final favoriteKey = _favoriteStorageKey(user?.uid);
      final favorites = _favoriteDestinationNames.toSet().toList();
      await prefs.setStringList(favoriteKey, favorites);

      if (user != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'favoriteDestinations': favorites,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _fetchLiveAlerts() async {
    setState(() => _isLoadingAlerts = true);
    try {
      final apiService = FastApiService();
      Map<String, String>? queryParams;

      try {
        // Attempt to get location with 3s timeout to avoid hanging dashboard
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
        ).timeout(const Duration(seconds: 3));
        queryParams = {
          'lat': position.latitude.toString(),
          'lon': position.longitude.toString(),
        };
      } catch (e) {
        debugPrint('Dashboard: Location fetch failed, using default: $e');
      }

      final alerts = await apiService.get('/api/alerts/', queryParams: queryParams);
      if (mounted) {
        setState(() {
          _liveAlerts = List<Map<String, dynamic>>.from(alerts);
          _isLoadingAlerts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAlerts = false);
      }
    }
  }

  void _refreshDashboard() {
    _fetchLiveAlerts();
    if (mounted) setState(() {});
  }

  Future<void> _openRouteAndRefresh(String route) async {
    await Navigator.pushNamed(context, route);
    if (!mounted) return;
    _refreshDashboard();
  }

  Future<void> _onBottomNavTap(int index) async {
    if (index == _selectedTabIndex) return;
    setState(() => _selectedTabIndex = index);
    switch (index) {
      case 0:
      case 1:
        return;
      case 2:
        await _openRouteAndRefresh('/chat');
        break;
      case 3:
        await _openRouteAndRefresh('/diary');
        break;
      case 4:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSettings()),
        );
        _loadUserData();
        break;
      default:
        break;
    }
    if (mounted) {
      setState(() => _selectedTabIndex = 0);
    }
  }

  Future<int> _fetchReminderCount() async {
    try {
      final apiService = FastApiService();
      final reminders = await apiService.get('/api/reminders/');
      if (reminders is List) return reminders.length;
    } catch (_) {}
    return 0;
  }

  Future<double> _fetchExpenseTotal() async {
    try {
      final apiService = FastApiService();
      final expenses = await apiService.get('/api/expenses/');
      if (expenses is List) {
        double total = 0.0;
        for (final item in expenses) {
          if (item is Map<String, dynamic>) {
            total += (item['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
        return total;
      }
    } catch (_) {}
    return 0.0;
  }

  Future<List<Map<String, dynamic>>> _fetchUpcomingReminders() async {
    try {
      final apiService = FastApiService();
      final reminders = await apiService.get('/api/reminders/');
      if (reminders is! List) return [];

      final parsed = <Map<String, dynamic>>[];
      final now = DateTime.now();

      for (final item in reminders) {
        if (item is! Map<String, dynamic>) continue;
        if ((item['status'] ?? 'pending').toString().toLowerCase() == 'completed') {
          continue;
        }
        // FIX: Ensure datetime is parsed and converted to LOCAL time using robust utility
        final localDt = fyp_date.DateUtils.parseToLocal((item['datetime'] ?? '').toString());
        
        parsed.add({
          ...item,
          '_localDt': localDt, // Cache for sorting
          '_isOverdue': localDt.isBefore(now),
        });
      }
      
      parsed.sort((a, b) {
        final adt = a['_localDt'] as DateTime;
        final bdt = b['_localDt'] as DateTime;
        return adt.compareTo(bdt);
      });
      return parsed.take(3).toList();
    } catch (_) {
      return [];
    }
  }

  void _showFeedbackPanel() {
    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF333252), Color(0xFF40315E)],
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
                        const SnackBar(content: Text("Report feature coming soon")),
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
      ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
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
              onPressed: () {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      backgroundColor: theme.scaffoldBackgroundColor,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: _onBottomNavTap,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite), label: 'Favorites'),
          NavigationDestination(icon: Icon(Icons.chat_outlined), selectedIcon: Icon(Icons.chat), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'Diary'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
      body: _selectedTabIndex == 1 ? _buildFavoritesView(theme) : CustomScrollView(
        slivers: [
          _buildAppBar(theme),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeCard(theme),
                  const SizedBox(height: 14),
                  _buildStartJourneyCard(),
                  const SizedBox(height: 18),
                  _buildSearchBar(theme),
                  const SizedBox(height: 24),
                  _buildDestinationSection(
                    title: 'Trending Destination',
                    destinations: _getFilteredDestinations(trendingPakistanDestinations),
                    cardStyle: _DestinationCardStyle.featured,
                  ),
                  const SizedBox(height: 24),
                  _buildTravelAgenciesCard(theme),
                  const SizedBox(height: 24),
                  _buildDestinationSection(
                    title: 'Top Pick for Travelers',
                    destinations: _getFilteredDestinations(topPickPakistanDestinations),
                    cardStyle: _DestinationCardStyle.compact,
                  ),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Active Alerts', '/alerts', theme),
                  const SizedBox(height: 12),
                  _buildActiveAlertsSection(),
                  const SizedBox(height: 24),
                  _buildSectionHeader('Upcoming Reminders', '/reminders', theme),
                  const SizedBox(height: 12),
                  _buildActiveRemindersSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 180,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF1E66F5),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: Colors.white),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () => _openRouteAndRefresh('/alerts'),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProfileSettings(),
              ),
            ).then((_) {
               _loadUserData();
               _fetchLiveAlerts();
            });
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: NetworkImage(
                'https://images.unsplash.com/photo-1527631746610-bca00a040d60?q=80&w=1200&auto=format&fit=crop',
              ),
              fit: BoxFit.cover,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.travel_explore, color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Travio',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              'Your smart travel & lifestyle companion',
                              style: TextStyle(fontSize: 13, color: Colors.white70),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
  );
  }

  // ------------------------- Home UI Blocks -------------------------
  Widget _buildSearchBar(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.grey.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search destinations, features...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
              if (_searchQuery.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(Icons.close, color: Colors.grey.shade600, size: 20),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E66F5).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tune, size: 18, color: Color(0xFF1E66F5)),
                ),
            ],
          ),
        ),
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4),
            child: Text(
              'Showing results for "$_searchQuery"',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }


  Widget _buildDestinationSection({
    required String title,
    required List<PakistanDestination> destinations,
    required _DestinationCardStyle cardStyle,
  }) {
    final theme = Theme.of(context);
    final height = cardStyle == _DestinationCardStyle.featured ? 360.0 : 250.0;
    final width = cardStyle == _DestinationCardStyle.featured ? 255.0 : 220.0;

    // If no destinations match the search, show nothing
    if (destinations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DestinationListScreen(
                      title: title,
                      destinations: destinations,
                    ),
                  ),
                );
              },
              child: const Text('See All', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: destinations.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              return SizedBox(
                width: width,
                child: _DestinationCard(
                  destination: destinations[index],
                  style: cardStyle,
                  isFavorite: _favoriteDestinationNames.contains(destinations[index].name),
                  onFavoriteToggle: () => _toggleDestinationFavorite(destinations[index]),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DestinationDetailScreen(destination: destinations[index]),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ------------------------- Welcome Card -------------------------
  Widget _buildWelcomeCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E66F5), Color(0xFF4EA8FF)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(_userInitials,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome Back', style: TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 4),
                Text(_userName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartJourneyCard() {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/startJourney'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E66F5).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.navigation_rounded,
                  color: Color(0xFF1E66F5), size: 26),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Start Journey',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  SizedBox(height: 2),
                  Text('Tap to open map & plan your route',
                      style:
                          TextStyle(fontSize: 12, color: Colors.white54)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white38, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTravelAgenciesCard(ThemeData theme) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: AgencyListBottomSheet(
              agencies: TravelAgency.mockAgencies,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF5C6BC0).withValues(alpha: 0.9),
              const Color(0xFF3F51B5).withValues(alpha: 0.9),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.business, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Travel Agencies',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Book with trusted partners',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withValues(alpha: 0.6),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildStatCard(IconData icon, String value, String label, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark 
                  ? Colors.grey.shade800 
                  : color.withValues(alpha: 0.1), 
              borderRadius: BorderRadius.circular(12)
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }


  Widget _buildSectionHeader(String title, String? route, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        if (route != null)
          TextButton(
              onPressed: () => _openRouteAndRefresh(route),
              child: Text('View All',
                  style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600))),
      ],
    );
  }

  // ------------------------- Active Alerts -------------------------
  Widget _buildActiveAlertsSection() {
    if (_isLoadingAlerts) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_liveAlerts.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('No active alerts at the moment'),
      );
    }

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _liveAlerts.length,
        itemBuilder: (context, index) {
          final alert = _liveAlerts[index];
          final type = alert['type']?.toString().toLowerCase() ?? 'info';
          final color = type == 'traffic' ? Colors.red : (type == 'weather' ? Colors.orange : Colors.blue);
          final icon = type == 'traffic' ? Icons.traffic : (type == 'weather' ? Icons.wb_sunny : Icons.info);
          
          // Localization fix for alert time if available
          String timeText = alert['time']?.toString() ?? 'Just now';
          if (alert['created_at'] != null) {
            final dt = DateTime.tryParse(alert['created_at'].toString());
            if (dt != null) {
              timeText = DateFormat('h:mm a').format(dt.toLocal());
            }
          }

          return Container(
            margin: EdgeInsets.only(right: index < _liveAlerts.length - 1 ? 12 : 0),
            width: MediaQuery.of(context).size.width * 0.8,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: InkWell(
                onTap: () => _openRouteAndRefresh('/alerts'),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10)),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('Live',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(alert['title']?.toString() ?? (alert['message']?.toString().split(':').first ?? 'Alert'),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(alert['description']?.toString() ?? (alert['message']?.toString() ?? ''),
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(height: 8),
                      Text(timeText,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveRemindersSection() {
    final user = _authService.currentUser;
    if (user == null) return const SizedBox.shrink();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchUpcomingReminders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('No upcoming reminders'),
          );
        }

        return Column(
          children: snapshot.data!.map((data) {
            final title = data['title'] ?? 'Meeting';
            final dt = (data['_localDt'] as DateTime?) ?? DateTime.now();
            final isOverdue = (data['_isOverdue'] as bool?) ?? false;
            final timeText = fyp_date.DateUtils.formatForDashboard(dt);

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200)),
              child: InkWell(
                onTap: () => _openRouteAndRefresh('/reminders'),
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.alarm, color: Colors.red, size: 22),
                  ),
                  title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(timeText, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isOverdue ? 'Overdue' : 'Upcoming',
                      style: TextStyle(
                        fontSize: 11,
                        color: isOverdue ? Colors.red : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }


  List<PakistanDestination> _getFilteredDestinations(List<PakistanDestination> destinations) {
    if (_searchQuery.isEmpty) {
      return destinations;
    }
    final query = _searchQuery.toLowerCase();
    return destinations.where((destination) {
      return destination.name.toLowerCase().contains(query) ||
          destination.typeLabel.toLowerCase().contains(query) ||
          destination.province.toLowerCase().contains(query) ||
          destination.summary.toLowerCase().contains(query);
    }).toList();
  }

  void _toggleDestinationFavorite(PakistanDestination destination) {
    setState(() {
      if (_favoriteDestinationNames.contains(destination.name)) {
        _favoriteDestinationNames.remove(destination.name);
      } else {
        _favoriteDestinationNames.add(destination.name);
      }
    });
    _saveFavoriteDestinations();
  }

  Widget _buildFavoritesView(ThemeData theme) {
    final allDestinations = <PakistanDestination>[
      ...trendingPakistanDestinations,
      ...topPickPakistanDestinations,
    ];
    final uniqueDestinationMap = <String, PakistanDestination>{};
    for (final destination in allDestinations) {
      uniqueDestinationMap.putIfAbsent(destination.name, () => destination);
    }
    final favorites = uniqueDestinationMap.values
        .where((destination) => _favoriteDestinationNames.contains(destination.name))
        .toList();

    return SafeArea(
      child: favorites.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border, size: 56, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                    const SizedBox(height: 14),
                    Text(
                      'No favorite places yet',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the heart on any destination to add it here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: favorites.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final destination = favorites[index];
                return _DestinationCard(
                  destination: destination,
                  style: _DestinationCardStyle.compact,
                  isFavorite: true,
                  onFavoriteToggle: () => _toggleDestinationFavorite(destination),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DestinationDetailScreen(destination: destination),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  // ------------------------- Drawer -------------------------
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
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileSettings()),
                      ).then((_) => _loadUserData());
                    },
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: Center(
                        child: Text(_userInitials, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(_userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(_userEmail, style: const TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerTile(Icons.home_rounded, 'Home', () => Navigator.pop(context)),
                  _drawerTile(Icons.chat_bubble_outline, 'Chat', () => _openRouteAndRefresh('/chat')),
                  _drawerTile(Icons.notifications_active, 'Alerts', () => _openRouteAndRefresh('/alerts')),
                  _drawerTile(Icons.alarm, 'Reminders', () => _openRouteAndRefresh('/reminders')),
                  _drawerTile(Icons.book, 'Diary', () => _openRouteAndRefresh('/diary')),
                  _drawerTile(Icons.mic, 'Voice Notes', () => _openRouteAndRefresh('/voiceNotes')),
                  _drawerTile(Icons.account_balance_wallet, 'Expenses', () => _openRouteAndRefresh('/expenseTracker')),
                  _drawerTile(Icons.map_outlined, 'Journey History', () => _openRouteAndRefresh('/journeyHistory')),
                  _drawerTile(Icons.emergency_share_outlined, 'Emergency Contacts', () => _openRouteAndRefresh('/emergencyContacts')),
                  const SizedBox(height: 16),
                  _drawerTile(Icons.feedback, 'Feedback', _showFeedbackPanel),
                  const SizedBox(height: 16),
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
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
            const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}


class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.style,
    required this.onTap,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  final PakistanDestination destination;
  final _DestinationCardStyle style;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;

  @override
  Widget build(BuildContext context) {
    final isFeatured = style == _DestinationCardStyle.featured;
    final imageHeight = isFeatured ? 185.0 : 130.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                DestinationImage(
                  destination: destination,
                  height: imageHeight,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${destination.discount}% Off',
                      style: const TextStyle(
                        color: Color(0xFF1E66F5),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: InkWell(
                    onTap: onFavoriteToggle,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.red : Colors.black87,
                      size: 20,
                    ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14, isFeatured ? 14 : 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          destination.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isFeatured ? 18 : 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '\$${destination.pricePerDay}/day',
                        style: TextStyle(
                          color: const Color(0xFF111827),
                          fontSize: isFeatured ? 16 : 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFF6B7280), size: 18),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          destination.province,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E66F5),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Text(
                          'Details',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (isFeatured) ...[
                    const SizedBox(height: 12),
                    Text(
                      destination.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF6B7280), height: 1.35, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(destination.icon, size: 18, color: const Color(0xFF1E66F5)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            destination.typeLabel,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1E66F5)),
                          ),
                        ),
                        const Icon(Icons.star, color: Color(0xFFFFC107), size: 18),
                        const SizedBox(width: 4),
                        Text(destination.rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w900)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
