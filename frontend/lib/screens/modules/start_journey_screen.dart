import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../models/journey_entry.dart';
import '../../services/active_journey.dart';
import '../../services/trip_api_service.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import 'alerts_module.dart';

class StartJourneyScreen extends StatefulWidget {
  const StartJourneyScreen({super.key});

  @override
  State<StartJourneyScreen> createState() => _StartJourneyScreenState();
}

class _StartJourneyScreenState extends State<StartJourneyScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _fromCtrl = TextEditingController();
  final TextEditingController _toCtrl = TextEditingController();
  final FocusNode _toFocus = FocusNode();

  LatLng _center = const LatLng(33.6844, 73.0479);
  LatLng? _fromLatLng;
  LatLng? _toLatLng;
  List<LatLng> _routePoints = [];

  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  bool _journeyStarted = false;
  bool _journeyActive = false;

  String _selectedTransport = 'car';

  /// Distance returned by OSRM (km), null until first route fetch.
  double? _routeDistanceKm;

  /// Travel duration returned by OSRM (minutes), null until first route fetch.
  int? _routeDurationMin;

  static const _transports = [
    ('car', 'Mini', Icons.directions_car),
    ('bike', 'Moto', Icons.two_wheeler),
    ('train', 'City to City', Icons.train),
    ('flight', 'Plane', Icons.flight),
  ];

  final AuthService _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _initLocation();
    _restoreActiveJourney();
    _toFocus.addListener(() {
      if (mounted) setState(() => _showSuggestions = _toFocus.hasFocus);
    });
  }

  Future<void> _restoreActiveJourney() async {
    final saved = await ActiveJourney.load();
    if (!mounted || saved == null) return;
    setState(() {
      _journeyActive = true;
      _selectedTransport = saved.transport;
      _toCtrl.text = saved.toName;
      if (saved.toLat != null && saved.toLon != null) {
        _toLatLng = LatLng(saved.toLat!, saved.toLon!);
      }
      // Intentionally don't restore _fromLatLng / _fromCtrl.text here —
      // _initLocation() owns the From side (current GPS). _initLocation
      // will trigger _fetchRoute() once it knows the user's live location,
      // so the polyline always matches the green "you are here" marker
      // instead of a stale saved origin.
    });
    if (_fromLatLng != null && _toLatLng != null) {
      await _fetchRoute();
    }
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 8));

      final latlng = LatLng(pos.latitude, pos.longitude);
      final address = await _reverseGeocode(latlng);
      if (!mounted) return;
      setState(() {
        _fromLatLng = latlng;
        _center = latlng;
        _fromCtrl.text = address;
      });
      _mapController.move(latlng, 15);
      // If a destination is already set (e.g., the user re-opened the screen
      // with an active journey restored), fetch the route now that both ends
      // are known.
      if (_toLatLng != null) {
        await _fetchRoute();
      }
    } catch (_) {}
  }

  Future<String> _reverseGeocode(LatLng latlng) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${latlng.latitude}&lon=${latlng.longitude}&format=json',
      );
      final res = await http
          .get(uri, headers: {'Accept-Language': 'en'})
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final name = data['display_name']?.toString() ?? '';
        return name.split(',').take(3).join(', ');
      }
    } catch (_) {}
    return 'Current Location';
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url =
          'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=5&addressdetails=1';

      final res = await http
          .get(
            Uri.parse(url),
            headers: {'Accept-Language': 'en', 'User-Agent': 'TravelBuddy/1.0'},
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted && data is List) {
          setState(() {
            _suggestions = List<Map<String, dynamic>>.from(data);
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _suggestions = []);
    }
  }

  void _selectSuggestion(Map<String, dynamic> place) {
    final lat = double.parse(place['lat'].toString());
    final lon = double.parse(place['lon'].toString());
    final name = (place['display_name'] as String)
        .split(',')
        .take(3)
        .join(', ');

    setState(() {
      _toLatLng = LatLng(lat, lon);
      _toCtrl.text = name;
      _suggestions = [];
      _showSuggestions = false;
      // Picking a new destination drops back into "preparing new journey"
      // mode so the bottom button reverts to "Start My Journey" — otherwise
      // a previously-active journey would lock the user into the old
      // destination and they could never restart with a different one.
      _journeyActive = false;
      // Reset route stats — will be repopulated after _fetchRoute() completes.
      _routeDistanceKm = null;
      _routeDurationMin = null;
    });
    _toFocus.unfocus();

    if (_fromLatLng != null) {
      _fetchRoute();
    }
  }

  // ── Route ────────────────────────────────────────────────────────────────

  Future<void> _fetchRoute() async {
    if (_fromLatLng == null || _toLatLng == null) return;

    try {
      final uri = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/'
        '${_fromLatLng!.longitude},${_fromLatLng!.latitude};'
        '${_toLatLng!.longitude},${_toLatLng!.latitude}'
        '?overview=full&geometries=geojson',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = (data['routes'] as List)[0] as Map<String, dynamic>;
          final coords = route['geometry']['coordinates'] as List;

          // Extract distance (metres → km) and duration (seconds → minutes)
          final distM = (route['distance'] as num?)?.toDouble() ?? 0.0;
          final durS = (route['duration'] as num?)?.toDouble() ?? 0.0;

          setState(() {
            _routePoints = coords
                .map((c) => LatLng((c as List)[1] as double, c[0] as double))
                .toList();
            _routeDistanceKm = distM / 1000.0;
            _routeDurationMin = (durS / 60).round();
          });
          _fitMap();
        }
      }
    } catch (e) {
      setState(() => _routePoints = [_fromLatLng!, _toLatLng!]);
    }
  }

  // ── Route info helpers ────────────────────────────────────────────────────

  String _formatDuration() {
    if (_routeDurationMin == null) return '';
    final h = _routeDurationMin! ~/ 60;
    final m = _routeDurationMin! % 60;
    if (h > 0) return '${h}h ${m}min';
    return '${m}min';
  }

  String _formatArrivalTime() {
    if (_routeDurationMin == null) return '';
    final arrival = DateTime.now().add(Duration(minutes: _routeDurationMin!));
    final hour = arrival.hour;
    final minute = arrival.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '${h}:${minute.toString().padLeft(2, '0')} $period';
  }

  void _fitMap() {
    if (_fromLatLng == null || _toLatLng == null) return;
    final bounds = LatLngBounds.fromPoints([_fromLatLng!, _toLatLng!]);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(100)),
    );
  }

  Future<void> _startJourney() async {
    if (_toCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination')),
      );
      return;
    }

    setState(() => _journeyStarted = true);
    try {
      final uid = _auth.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        final entry = JourneyEntry(
          id: '',
          fromPlace: _fromCtrl.text.isEmpty
              ? 'Current Location'
              : _fromCtrl.text,
          toPlace: _toCtrl.text,
          departureTime: DateTime.now(),
          transport: _selectedTransport,
          foodItems: const [],
          notes: '',
          isCompleted: false,
          userId: uid,
        );
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('journeys')
            .add(entry.toFirestore());
      }

      // Persist active journey so Alerts page + Dashboard can read it.
      await ActiveJourney.save(
        fromName: _fromCtrl.text.isEmpty ? 'Current Location' : _fromCtrl.text,
        toName: _toCtrl.text,
        transport: _selectedTransport,
        departureTime: DateTime.now(),
        fromLat: _fromLatLng?.latitude,
        fromLon: _fromLatLng?.longitude,
        toLat: _toLatLng?.latitude,
        toLon: _toLatLng?.longitude,
        distanceKm: _routeDistanceKm,
        durationMin: _routeDurationMin,
      );

      // Create a backend Trip so new expenses/reminders/notes auto-scope to it
      // (enables per-trip chatbot answers). Best-effort; never blocks the UI.
      await TripApiService().startTrip(
        destination: _toCtrl.text,
        origin: _fromCtrl.text.isEmpty ? 'Current Location' : _fromCtrl.text,
        transport: _selectedTransport,
      );

      if (!mounted) return;
      setState(() => _journeyActive = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Journey started successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error starting journey')));
    } finally {
      if (mounted) setState(() => _journeyStarted = false);
    }
  }

  Future<void> _endJourney() async {
    await ActiveJourney.clear();
    // Mark the backend trip completed so its records stay grouped. Best-effort.
    await TripApiService().completeActiveTrip();
    if (!mounted) return;
    setState(() => _journeyActive = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Journey ended.'),
        backgroundColor: Colors.blueGrey,
      ),
    );
  }

  Future<void> _openActiveAlerts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AlertsModule()),
    );
    if (!mounted) return;
    // After returning, re-check journey state (user might have ended it from
    // the Alerts page).
    final stillActive = await ActiveJourney.isActive();
    if (mounted && stillActive != _journeyActive) {
      setState(() => _journeyActive = stillActive);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // 1. Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13,
              onTap: (_, _) {
                _toFocus.unfocus();
                setState(() => _showSuggestions = false);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.travio.fyp',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: primaryColor,
                      strokeWidth: 5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_fromLatLng != null)
                    Marker(
                      point: _fromLatLng!,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.my_location,
                        color: Colors.green,
                        size: 30,
                      ),
                    ),
                  if (_toLatLng != null)
                    Marker(
                      point: _toLatLng!,
                      width: 40,
                      height: 40,
                      child: Icon(
                        Icons.location_on,
                        color: primaryColor,
                        size: 35,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. Search Top Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.28 : 0.10,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: isDark
                            ? AppColors.borderDark
                            : AppColors.borderLight,
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        _buildSearchField(
                          controller: _fromCtrl,
                          hint: 'From',
                          icon: Icons.my_location,
                          iconColor: Colors.green,
                          enabled: false,
                        ),
                        const Divider(height: 1),
                        _buildSearchField(
                          controller: _toCtrl,
                          hint: 'Search Destination...',
                          icon: Icons.location_on,
                          iconColor: primaryColor,
                          focusNode: _toFocus,
                          onChanged: _searchPlaces,
                        ),
                      ],
                    ),
                  ),
                  if (_showSuggestions && _suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 250),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isDark
                            ? const []
                            : const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 10,
                                ),
                              ],
                        border: Border.all(
                          color: isDark
                              ? AppColors.borderDark
                              : AppColors.borderLight,
                        ),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _suggestions[i];
                          return ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              p['display_name'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            onTap: () => _selectSuggestion(p),
                          );
                        },
                      ),
                    ),
                  if (_journeyActive)
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_run,
                            color: Colors.green,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Journey in progress → ${_toCtrl.text}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w700,
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

          // 3. Bottom Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                  ),
                ),
                boxShadow: isDark
                    ? const []
                    : const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 20,
                          offset: Offset(0, -5),
                        ),
                      ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _transports.map((t) {
                        final isSelected = _selectedTransport == t.$1;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedTransport = t.$1),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryColor
                                  : (isDark
                                        ? AppColors.surfaceDarkElevated
                                        : AppColors.bgLight),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : (isDark
                                          ? AppColors.borderDark
                                          : AppColors.borderLight),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  t.$3,
                                  color: isSelected
                                      ? Colors.white
                                      : theme.colorScheme.onSurfaceVariant,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  t.$2,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // ── Route info card ──────────────────────────────────
                  if (_routeDistanceKm != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          _RouteStatItem(
                            icon: Icons.straighten_rounded,
                            label:
                                '${_routeDistanceKm!.toStringAsFixed(1)} km',
                            sublabel: 'Distance',
                            color: primaryColor,
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: primaryColor.withValues(alpha: 0.20),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _RouteStatItem(
                            icon: Icons.timer_rounded,
                            label: _formatDuration(),
                            sublabel: 'Travel Time',
                            color: primaryColor,
                          ),
                          Container(
                            width: 1,
                            height: 36,
                            color: primaryColor.withValues(alpha: 0.20),
                            margin: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          _RouteStatItem(
                            icon: Icons.schedule_rounded,
                            label: _formatArrivalTime(),
                            sublabel: 'ETA',
                            color: primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (!_journeyActive)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _journeyStarted ? null : _startJourney,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _journeyStarted
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Start My Journey',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _openActiveAlerts,
                            icon: const Icon(
                              Icons.notifications_active,
                              color: Colors.white,
                            ),
                            label: const Text(
                              'Show Active Alerts',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _endJourney,
                            icon: const Icon(
                              Icons.stop_circle_outlined,
                              size: 20,
                            ),
                            label: const Text(
                              'End Journey',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.redAccent,
                              side: const BorderSide(color: Colors.redAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color iconColor,
    bool enabled = true,
    FocusNode? focusNode,
    Function(String)? onChanged,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      onChanged: onChanged,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        prefixIcon: Icon(icon, color: iconColor, size: 22),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

// ── Route stat column widget ───────────────────────────────────────────────

class _RouteStatItem extends StatelessWidget {
  const _RouteStatItem({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sublabel,
            style: TextStyle(
              color: color.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
