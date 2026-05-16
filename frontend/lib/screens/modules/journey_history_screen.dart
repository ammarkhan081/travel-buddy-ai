import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/journey_entry.dart';
import '../../services/auth_service.dart';

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

  static const _transportIcons = {
    'car': Icons.directions_car,
    'bus': Icons.directions_bus,
    'train': Icons.train,
    'flight': Icons.flight,
    'walk': Icons.directions_walk,
    'bike': Icons.directions_bike,
  };

  static const _transportColors = {
    'car': Colors.blue,
    'bus': Colors.orange,
    'train': Colors.purple,
    'flight': Colors.indigo,
    'walk': Colors.green,
    'bike': Colors.teal,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Journey History',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E66F5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddJourneySheet(context),
        backgroundColor: const Color(0xFF1E66F5),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Journey', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<QuerySnapshot>(
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
          final journeys =
              docs.map((d) => JourneyEntry.fromFirestore(d)).toList();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: journeys.length,
            itemBuilder: (context, index) =>
                _JourneyCard(
                  journey: journeys[index],
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
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 72,
              color: theme.colorScheme.primary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No journeys yet',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Tap "+ New Journey" to log your first trip.',
              style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Future<void> _deleteJourney(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Journey'),
        content:
            const Text('Are you sure you want to delete this journey entry?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                const Text('Delete', style: TextStyle(color: Colors.white)),
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Arrived at ${journey.toPlace}! Journey completed.'),
          backgroundColor: Colors.green,
        ),
      );
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
    required this.isFirst,
    required this.isLast,
    required this.transportIcons,
    required this.transportColors,
    required this.onDelete,
    required this.onMarkArrived,
  });

  final JourneyEntry journey;
  final bool isFirst;
  final bool isLast;
  final Map<String, IconData> transportIcons;
  final Map<String, Color> transportColors;
  final VoidCallback onDelete;
  final VoidCallback? onMarkArrived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = transportColors[journey.transport] ?? Colors.blue;
    final icon = transportIcons[journey.transport] ?? Icons.directions_car;
    final df = DateFormat('EEE, d MMM yyyy  •  h:mm a');

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
                  Container(width: 2, height: 12, color: Colors.grey.shade300),
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
                        width: 2, color: Colors.grey.shade300),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Card
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${journey.fromPlace}  →  ${journey.toPlace}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: journey.isCompleted
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            journey.isCompleted ? 'Completed' : 'Ongoing',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: journey.isCompleted
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Departure
                    _InfoRow(
                      icon: Icons.flight_takeoff,
                      label: 'Departed',
                      value: df.format(journey.departureTime),
                      color: Colors.blue,
                    ),
                    // Arrival
                    if (journey.arrivalTime != null) ...[
                      const SizedBox(height: 6),
                      _InfoRow(
                        icon: Icons.flight_land,
                        label: 'Arrived',
                        value: df.format(journey.arrivalTime!),
                        color: Colors.green,
                      ),
                      const SizedBox(height: 6),
                      _InfoRow(
                        icon: Icons.timer_outlined,
                        label: 'Duration',
                        value: _duration(
                            journey.departureTime, journey.arrivalTime!),
                        color: Colors.purple,
                      ),
                    ],
                    // Transport
                    const SizedBox(height: 6),
                    _InfoRow(
                      icon: icon,
                      label: 'Transport',
                      value: journey.transport[0].toUpperCase() +
                          journey.transport.substring(1),
                      color: color,
                    ),
                    // Food
                    if (journey.foodItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.restaurant,
                              size: 16, color: Colors.deepOrange),
                          const SizedBox(width: 6),
                          const Text('Food: ',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.deepOrange)),
                          Expanded(
                            child: Text(
                              journey.foodItems.join(', '),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Notes
                    if (journey.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          journey.notes,
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                    // Actions
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (onMarkArrived != null)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: onMarkArrived,
                              icon: const Icon(Icons.location_on, size: 16),
                              label: const Text("Mark Arrived"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        if (onMarkArrived != null) const SizedBox(width: 8),
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          tooltip: 'Delete journey',
                        ),
                      ],
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text('$label: ',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13, color: Colors.grey.shade700)),
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
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          color: Colors.white,
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Text('New Journey',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(),
            // Form
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(20),
                  children: [
                    _buildTextField(_fromCtrl, 'From (departure place)',
                        Icons.flight_takeoff, 'Enter departure place'),
                    const SizedBox(height: 14),
                    _buildTextField(_toCtrl, 'To (destination)',
                        Icons.flight_land, 'Enter destination'),
                    const SizedBox(height: 20),
                    // Departure time
                    const Text('Departure Date & Time',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickDateTime,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: Color(0xFF1E66F5), size: 20),
                            const SizedBox(width: 10),
                            Text(
                              DateFormat('EEE, d MMM yyyy  •  h:mm a')
                                  .format(_departureTime),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Transport
                    const Text('Mode of Transport',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
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
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFF1E66F5)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFF1E66F5)
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(t.$3,
                                    size: 16,
                                    color: selected
                                        ? Colors.white
                                        : Colors.grey.shade700),
                                const SizedBox(width: 6),
                                Text(t.$2,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                    )),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    // Food
                    const Text('Food Eaten',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _foodCtrl,
                            decoration: InputDecoration(
                              hintText: 'e.g. Biryani, Chai...',
                              prefixIcon: const Icon(Icons.restaurant,
                                  color: Colors.deepOrange, size: 20),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                      color: Colors.grey.shade300)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _addFood,
                          icon: const Icon(Icons.add),
                          style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF1E66F5)),
                        ),
                      ],
                    ),
                    if (_foodItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _foodItems
                            .map((f) => Chip(
                                  label: Text(f),
                                  deleteIcon: const Icon(Icons.close,
                                      size: 14),
                                  onDeleted: () =>
                                      setState(() => _foodItems.remove(f)),
                                  backgroundColor: Colors.deepOrange
                                      .withValues(alpha: 0.1),
                                  side: BorderSide(
                                      color: Colors.deepOrange
                                          .withValues(alpha: 0.3)),
                                ))
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
                            borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
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
                          backgroundColor: const Color(0xFF1E66F5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Text('Save Journey',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
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
      TextEditingController ctrl, String label, IconData icon, String hint) {
    return TextFormField(
      controller: ctrl,
      validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'This field is required' : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF1E66F5)),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
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
      _departureTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
          SnackBar(content: Text('Error saving journey: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
