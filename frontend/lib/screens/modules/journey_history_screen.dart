import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/journey_entry.dart';
import '../../models/emergency_contact.dart';
import '../../services/auth_service.dart';
import '../../services/trip_api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';
import '../../widgets/module_fab.dart';

class JourneyHistoryScreen extends StatefulWidget {
  const JourneyHistoryScreen({super.key});

  @override
  State<JourneyHistoryScreen> createState() => _JourneyHistoryScreenState();
}

class _JourneyHistoryScreenState extends State<JourneyHistoryScreen> {
  final AuthService _auth = AuthService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String get _uid => _auth.currentUser?.uid ?? '';

  CollectionReference get _journeysRef =>
      _db.collection('users').doc(_uid).collection('journeys');

  CollectionReference get _contactsRef =>
      _db.collection('users').doc(_uid).collection('emergency_contacts');

  static const _smsChannel = MethodChannel('com.example.fyp/sms');

  static const _transportIcons = {
    'car': Icons.directions_car,
    'bus': Icons.directions_bus,
    'train': Icons.train,
    'flight': Icons.flight,
    'walk': Icons.directions_walk,
    'bike': Icons.directions_bike,
  };

  static const _transportColors = {
    'car': AppColors.infoBlue,
    'bus': AppColors.warning,
    'train': AppColors.primary,
    'flight': AppColors.primaryDark,
    'walk': AppColors.success,
    'bike': Colors.teal,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      floatingActionButton: ModuleFab(
        icon: Icons.add,
        label: 'New Journey',
        minWidth: 158,
        onPressed: () => _showAddJourneySheet(context),
      ),
      body: Column(
        children: [
          AppHeader(
            title: 'Journey History',
            subtitle: 'Trips, arrivals, and safety check-ins',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _journeysRef
                  .orderBy('departureTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _buildEmptyState(theme);
                }
                final journeys = docs
                    .map((d) => JourneyEntry.fromFirestore(d))
                    .toList();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: journeys.length,
                  itemBuilder: (context, index) => _JourneyCard(
                    journey: journeys[index],
                    number: journeys.length - index,
                    isFirst: index == 0,
                    isLast: index == journeys.length - 1,
                    transportIcons: _transportIcons,
                    transportColors: _transportColors,
                    onDelete: () => _deleteJourney(journeys[index].id),
                    onMarkArrived: journeys[index].isCompleted
                        ? null
                        : () => _markArrived(journeys[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: AppEmptyState(
          icon: Icons.route_rounded,
          title: 'No journeys yet',
          subtitle: 'Tap New Journey to log your first trip.',
          ctaLabel: 'New Journey',
          onCta: () => _showAddJourneySheet(context),
        ),
      ),
    );
  }

  Future<void> _deleteJourney(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Journey'),
        content: const Text(
          'Are you sure you want to delete this journey entry?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _journeysRef.doc(id).delete();
    }
  }

  Future<void> _markArrived(JourneyEntry journey) async {
    final now = DateTime.now();
    await _journeysRef.doc(journey.id).update({
      'arrivalTime': Timestamp.fromDate(now),
      'isCompleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Complete the active backend trip on arrival (best-effort).
    await TripApiService().completeActiveTrip();
    final smsResult = await _sendArrivalSmsToEmergencyContacts(journey, now);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            smsResult == null
                ? 'Arrived at ${journey.toPlace}! Journey completed.'
                : 'Arrived at ${journey.toPlace}! $smsResult',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<String?> _sendArrivalSmsToEmergencyContacts(
    JourneyEntry journey,
    DateTime arrivalTime,
  ) async {
    if (_uid.isEmpty || !Platform.isAndroid) return null;

    final snapshot = await _contactsRef.get();
    final contacts = snapshot.docs
        .map((doc) => EmergencyContact.fromFirestore(doc))
        .where((contact) => contact.phone.trim().isNotEmpty)
        .toList(growable: false);
    if (contacts.isEmpty) {
      return 'No emergency contacts found for arrival SMS.';
    }

    final smsStatus = await Permission.sms.request();
    if (!smsStatus.isGranted) {
      return 'SMS permission was not granted, so arrival SMS was not sent.';
    }

    final locationText = await _currentLocationLink();
    final timeStr = DateFormat('d/M/yyyy at HH:mm').format(arrivalTime);
    final message =
        'Hi! I have safely arrived at ${journey.toPlace} on $timeStr. '
        'My location: $locationText - Sent via Travio';

    var sentCount = 0;
    for (final contact in contacts) {
      final ok = await _sendDirectSms(contact.phone, message);
      if (ok) sentCount++;
    }

    if (sentCount == 0) {
      return 'Arrival SMS could not be sent. Please check SMS permission and SIM balance.';
    }
    return 'Arrival SMS sent to $sentCount contact${sentCount > 1 ? 's' : ''}.';
  }

  Future<String> _currentLocationLink() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'location unavailable';
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 6));
      return 'https://maps.google.com/?q=${position.latitude},${position.longitude}';
    } catch (_) {
      return 'location unavailable';
    }
  }

  Future<bool> _sendDirectSms(String phone, String message) async {
    try {
      await _smsChannel.invokeMethod('sendSms', {
        'phone': phone.trim(),
        'message': message,
      });
      return true;
    } catch (e) {
      debugPrint('Arrival SMS failed for $phone: $e');
      return false;
    }
  }

  void _showAddJourneySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddJourneySheet(
        onSave: (entry) async {
          await _journeysRef.add(entry.toFirestore());
        },
        userId: _uid,
      ),
    );
  }
}

// ─────────────────────────── Journey Card ────────────────────────────

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.journey,
    required this.number,
    required this.isFirst,
    required this.isLast,
    required this.transportIcons,
    required this.transportColors,
    required this.onDelete,
    required this.onMarkArrived,
  });

  final JourneyEntry journey;
  final int number;
  final bool isFirst;
  final bool isLast;
  final Map<String, IconData> transportIcons;
  final Map<String, Color> transportColors;
  final VoidCallback onDelete;
  final VoidCallback? onMarkArrived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = transportColors[journey.transport] ?? Colors.blue;
    final icon = transportIcons[journey.transport] ?? Icons.directions_car;
    // Reference-style date: line 1 = date, line 2 = time.
    final dfDate = DateFormat('EEE, d MMM yyyy');
    final dfTime = DateFormat('h:mm a');
    // Split destination into a bold primary line and a lighter secondary line.
    final destParts = journey.toPlace.split(',');
    final destPrimary = destParts.isNotEmpty
        ? destParts.take(2).join(',').trim()
        : journey.toPlace;
    final destSecondary = destParts.length > 2
        ? destParts.sublist(2).join(',').trim()
        : '';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                if (!isFirst)
                  Container(
                    width: 2,
                    height: 12,
                    color: isDark
                        ? AppColors.borderDark
                        : AppColors.borderLight,
                  ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isDark
                          ? AppColors.borderDark
                          : AppColors.borderLight,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
                boxShadow: isDark ? const [] : AppShadows.softCard,
              ),
              // Left accent bar (reference style) via a leading colored strip.
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 5, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Top row: status pill + journey number ──
                            Row(
                              children: [
                                _StatusPill(isCompleted: journey.isCompleted),
                                const Spacer(),
                                Text(
                                  'Journey #$number',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.textTertiaryDark
                                        : AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // ── Destination: pin + two-line place ──
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.location_on_outlined,
                                    size: 20,
                                    color: isDark
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        destPrimary,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          height: 1.2,
                                          color: isDark
                                              ? AppColors.textPrimaryDark
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      if (destSecondary.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          destSecondary,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: isDark
                                                ? AppColors.textSecondaryDark
                                                : AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Divider(
                              height: 1,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.07),
                            ),
                            const SizedBox(height: 14),
                            // ── Two-column grid: Departed | Transport ──
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _GridCell(
                                      icon: Icons.flight_takeoff,
                                      label: 'Departed',
                                      lines: [
                                        dfDate.format(journey.departureTime),
                                        dfTime.format(journey.departureTime),
                                      ],
                                      accent: AppColors.infoBlue,
                                      isDark: isDark,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: VerticalDivider(
                                      width: 1,
                                      thickness: 1,
                                      color:
                                          (isDark ? Colors.white : Colors.black)
                                              .withValues(alpha: 0.07),
                                    ),
                                  ),
                                  Expanded(
                                    child: journey.arrivalTime != null
                                        ? _GridCell(
                                            icon: Icons.flight_land,
                                            label: 'Arrived',
                                            lines: [
                                              dfDate.format(
                                                journey.arrivalTime!,
                                              ),
                                              dfTime.format(
                                                journey.arrivalTime!,
                                              ),
                                            ],
                                            accent: AppColors.success,
                                            isDark: isDark,
                                          )
                                        : _GridCell(
                                            icon: icon,
                                            label: 'Transport',
                                            lines: [
                                              journey.transport[0]
                                                      .toUpperCase() +
                                                  journey.transport.substring(1),
                                            ],
                                            accent: color,
                                            isDark: isDark,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            // Extra meta when completed (transport + duration).
                            if (journey.arrivalTime != null) ...[
                              const SizedBox(height: 12),
                              _InfoRow(
                                icon: icon,
                                label: 'Transport',
                                value:
                                    journey.transport[0].toUpperCase() +
                                    journey.transport.substring(1),
                                color: color,
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.timer_outlined,
                                label: 'Duration',
                                value: _duration(
                                  journey.departureTime,
                                  journey.arrivalTime!,
                                ),
                                color: AppColors.primary,
                              ),
                            ],
                            // Food
                            if (journey.foodItems.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _InfoRow(
                                icon: Icons.restaurant,
                                label: 'Food',
                                value: journey.foodItems.join(', '),
                                color: Colors.deepOrange,
                              ),
                            ],
                            // Notes
                            if (journey.notes.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.surfaceDarkElevated
                                      : AppColors.bgLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  journey.notes,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                            // Actions
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                if (onMarkArrived != null)
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: onMarkArrived,
                                      icon: const Icon(
                                        Icons.location_on,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Mark Arrived',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (onMarkArrived != null)
                                  const SizedBox(width: 10),
                                Material(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: onDelete,
                                    borderRadius: BorderRadius.circular(12),
                                    child: const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Icon(
                                        Icons.delete_outline,
                                        color: AppColors.danger,
                                        size: 20,
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _duration(DateTime from, DateTime to) {
    final diff = to.difference(from);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

// ── Status pill (Ongoing / Completed) ──
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isCompleted});

  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    final c = isCompleted ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isCompleted ? 'Completed' : 'Ongoing',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: c,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Grid cell (Departed / Arrived / Transport column) ──
class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.icon,
    required this.label,
    required this.lines,
    required this.accent,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final List<String> lines;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final l in lines)
          Text(
            l,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────── Add Journey Bottom Sheet ────────────────────────

class _AddJourneySheet extends StatefulWidget {
  const _AddJourneySheet({required this.onSave, required this.userId});

  final Future<void> Function(JourneyEntry) onSave;
  final String userId;

  @override
  State<_AddJourneySheet> createState() => _AddJourneySheetState();
}

class _AddJourneySheetState extends State<_AddJourneySheet> {
  final _formKey = GlobalKey<FormState>();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _foodCtrl = TextEditingController();

  DateTime _departureTime = DateTime.now();
  String _transport = 'car';
  final List<String> _foodItems = [];
  bool _saving = false;

  static const _transports = [
    ('car', 'Car', Icons.directions_car),
    ('bus', 'Bus', Icons.directions_bus),
    ('train', 'Train', Icons.train),
    ('flight', 'Flight', Icons.flight),
    ('walk', 'Walk', Icons.directions_walk),
    ('bike', 'Bike', Icons.directions_bike),
  ];

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _notesCtrl.dispose();
    _foodCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Text(
                    'New Journey',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildTextField(
                      _fromCtrl,
                      'From (departure place)',
                      Icons.flight_takeoff,
                      'Enter departure place',
                    ),
                    const SizedBox(height: 14),
                    _buildTextField(
                      _toCtrl,
                      'To (destination)',
                      Icons.flight_land,
                      'Enter destination',
                    ),
                    const SizedBox(height: 20),
                    // Departure time
                    Text(
                      'Departure Date & Time',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickDateTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? AppColors.borderDark
                                : AppColors.borderLight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat(
                                'EEE, d MMM yyyy  •  h:mm a',
                              ).format(_departureTime),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Transport
                    Text(
                      'Mode of Transport',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _transports.map((t) {
                        final selected = _transport == t.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _transport = t.$1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : (isDark
                                        ? AppColors.surfaceDarkElevated
                                        : AppColors.bgLight),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : (isDark
                                          ? AppColors.borderDark
                                          : AppColors.borderLight),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  t.$3,
                                  size: 16,
                                  color: selected
                                      ? Colors.white
                                      : (isDark
                                            ? AppColors.textSecondaryDark
                                            : AppColors.textSecondary),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  t.$2,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? Colors.white
                                        : (isDark
                                              ? AppColors.textSecondaryDark
                                              : AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    // Food
                    Text(
                      'Food Eaten',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _foodCtrl,
                            decoration: InputDecoration(
                              hintText: 'e.g. Biryani, Chai...',
                              prefixIcon: const Icon(
                                Icons.restaurant,
                                color: Colors.deepOrange,
                                size: 20,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.grey.shade300,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _addFood,
                          icon: const Icon(Icons.add),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    if (_foodItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _foodItems
                            .map(
                              (f) => Chip(
                                label: Text(f),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () =>
                                    setState(() => _foodItems.remove(f)),
                                backgroundColor: Colors.deepOrange.withValues(
                                  alpha: 0.1,
                                ),
                                side: BorderSide(
                                  color: Colors.deepOrange.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // Notes
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'Any additional details...',
                        prefixIcon: const Icon(Icons.notes),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Journey',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon,
    String hint,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: ctrl,
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'This field is required' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
    );
  }

  void _addFood() {
    final text = _foodCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _foodItems.add(text);
        _foodCtrl.clear();
      });
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departureTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureTime),
    );
    if (time == null) return;
    setState(() {
      _departureTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final entry = JourneyEntry(
        id: '',
        fromPlace: _fromCtrl.text.trim(),
        toPlace: _toCtrl.text.trim(),
        departureTime: _departureTime,
        transport: _transport,
        foodItems: List.from(_foodItems),
        notes: _notesCtrl.text.trim(),
        isCompleted: false,
        userId: widget.userId,
      );
      await widget.onSave(entry);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving journey: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
