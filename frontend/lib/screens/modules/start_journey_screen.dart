import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../models/journey_entry.dart';
import '../../services/auth_service.dart';
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
  bool _loadingSuggestions = false;
  bool _showSuggestions = false;
  bool _loadingLocation = true;
  bool _calculatingRoute = false;
  bool _journeyStarted = false;
  bool _journeyActive = false;

  String _selectedTransport = 'car';

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
    _toFocus.addListener(() {
      if (mounted) setState(() => _showSuggestions = _toFocus.hasFocus);
    });
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
    setState(() => _loadingLocation = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() => _loadingLocation = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));

      final latlng = LatLng(pos.latitude, pos.longitude);
      final address = await _reverseGeocode(latlng);
      if (!mounted) return;
      setState(() {
        _fromLatLng = latlng;
        _center = latlng;
        _fromCtrl.text = address;
        _loadingLocation = false;
      });
      _mapController.move(latlng, 15);
    } catch (_) {
      if (mounted) setState(() => _loadingLocation = false);
    }
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
    setState(() => _loadingSuggestions = true);
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = 'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=5&addressdetails=1';
      
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'Accept-Language': 'en',
          'User-Agent': 'TravelBuddy/1.0',
        },
      ).timeout(const Duration(seconds: 5));
      
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
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
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
    });
    _toFocus.unfocus();
    
    if (_fromLatLng != null) {
      _fetchRoute();
    }
  }

  // ── Route ────────────────────────────────────────────────────────────────

  Future<void> _fetchRoute() async {
    if (_fromLatLng == null || _toLatLng == null) return;
    
    setState(() => _calculatingRoute = true);
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
          final coords = (data['routes'] as List)[0]['geometry']['coordinates'] as List;
          setState(() {
            _routePoints = coords
                .map((c) => LatLng(
                      (c as List)[1] as double,
                      c[0] as double,
                    ))
                .toList();
          });
          _fitMap();
        }
      }
    } catch (e) {
      setState(() => _routePoints = [_fromLatLng!, _toLatLng!]);
    } finally {
      if (mounted) setState(() => _calculatingRoute = false);
    }
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
          fromPlace: _fromCtrl.text.isEmpty ? 'Current Location' : _fromCtrl.text,
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
      
      if (!mounted) return;
      setState(() => _journeyActive = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Journey started successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error starting journey')),
      );
    } finally {
      if (mounted) setState(() => _journeyStarted = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

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
              onTap: (_, __) {
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
                      child: Icon(Icons.my_location, color: Colors.green, size: 30),
                    ),
                  if (_toLatLng != null)
                    Marker(
                      point: _toLatLng!,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.location_on, color: primaryColor, size: 35),
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
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
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
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _suggestions[i];
                          return ListTile(
                            leading: const Icon(Icons.place_outlined),
                            title: Text(p['display_name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.colorScheme.onSurface)),
                            onTap: () => _selectSuggestion(p),
                          );
                        },
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
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _transports.map((t) {
                        final isSelected = _selectedTransport == t.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedTransport = t.$1),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? primaryColor : theme.colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(t.$3, color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  t.$2,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : theme.colorScheme.onSurface,
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
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _journeyStarted ? null : _startJourney,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _journeyStarted
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Start My Journey',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                    ),
                  ),
                  if (_journeyActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: IconButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AlertsModule()),
                          );
                        },
                        icon: const Icon(Icons.warning, color: Colors.red, size: 32),
                        tooltip: 'View Alerts',
                      ),
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
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      onChanged: onChanged,
      style: const TextStyle(fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: iconColor, size: 22),
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
