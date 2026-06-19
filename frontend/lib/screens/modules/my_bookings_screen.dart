import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/booking.dart';
import '../../services/booking_service.dart';
import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _bookingService = BookingService();

  List<BookingModel> _bookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      final bookings = await _bookingService.getMyBookings();
      if (mounted) setState(() => _bookings = bookings);
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'Could not load bookings: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshBookings() async {
    try {
      final bookings = await _bookingService.getMyBookings();
      if (mounted) setState(() => _bookings = bookings);
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'Could not refresh bookings: $e',
        isError: true,
      );
    }
  }

  Future<void> _confirmCancel(BookingModel booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(
          'Your ${booking.destinationName} booking will be cancelled. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _bookingService.cancelBooking(booking.id);
      await _refreshBookings();
      if (!mounted) return;
      UIFeedback.showSnackBar(context, 'Booking cancelled.');
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'Could not cancel booking: $e',
        isError: true,
      );
    }
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return _dateFormat.format(parsed);
  }

  Future<void> _showTripDiarySheet(BookingModel booking) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TripDiarySheet(
        destinationName: booking.destinationName,
        fromDate: booking.travelDate,
        returnDate: booking.returnDate,
        bookingId: booking.id,
      ),
    );
    if (result == true && mounted) {
      UIFeedback.showSnackBar(
        context,
        '${booking.destinationName} trip diary generated! Check your diary.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'My Bookings',
            subtitle: 'Your upcoming & past tours',
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bookings.isEmpty
                    ? RefreshIndicator(
                        onRefresh: _refreshBookings,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.10),
                                      borderRadius:
                                          BorderRadius.circular(24),
                                    ),
                                    child: const Icon(
                                      Icons.luggage_rounded,
                                      size: 44,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No bookings yet.',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: isDark
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Start exploring Pakistan and\nbook your first tour!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
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
                      )
                    : RefreshIndicator(
                        onRefresh: _refreshBookings,
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 16, 16, 32),
                          itemCount: _bookings.length,
                          itemBuilder: (context, index) {
                            final booking = _bookings[index];
                            final dateText = booking.returnDate == null
                                ? '${_formatDate(booking.travelDate)} • One-way'
                                : '${_formatDate(booking.travelDate)} → ${_formatDate(booking.returnDate!)}';
                            return _BookingCard(
                              booking: booking,
                              dateText: dateText,
                              isDark: isDark,
                              onCancel: () => _confirmCancel(booking),
                              onGenerateDiary: () => _showTripDiarySheet(booking),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.dateText,
    required this.isDark,
    required this.onCancel,
    required this.onGenerateDiary,
  });

  final BookingModel booking;
  final String dateText;
  final bool isDark;
  final VoidCallback onCancel;
  final VoidCallback onGenerateDiary;

  Color get _statusColor {
    switch (booking.status) {
      case 'Completed':
        return AppColors.success;
      case 'Confirmed':
        return AppColors.success;
      case 'Cancelled':
        return AppColors.textTertiary;
      default: // Pending
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: destination name + status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.destinationName,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      booking.agencyName,
                      style: TextStyle(
                        color: secondaryText,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(label: booking.status, color: _statusColor),
            ],
          ),
          const SizedBox(height: 14),

          // Dates
          _BookingInfoRow(
            icon: Icons.calendar_month,
            text: dateText,
            isDark: isDark,
          ),
          const SizedBox(height: 8),

          // Travelers
          _BookingInfoRow(
            icon: Icons.groups_outlined,
            text:
                '${booking.numPeople} traveler${booking.numPeople == 1 ? '' : 's'}',
            isDark: isDark,
          ),

          // Email (show only if present)
          if (booking.userEmail != null && booking.userEmail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _BookingInfoRow(
              icon: Icons.email_outlined,
              text: booking.userEmail!,
              isDark: isDark,
            ),
          ],

          // Special requests (show only if present)
          if (booking.specialRequests != null &&
              booking.specialRequests!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _BookingInfoRow(
              icon: Icons.notes_rounded,
              text: booking.specialRequests!,
              isDark: isDark,
            ),
          ],

          // Footer actions — shown for non-cancelled bookings
          if (booking.status != 'Cancelled') ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: booking.status == 'Pending'
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.start,
              children: [
                // Write Trip Diary button — always shown for non-cancelled
                TextButton.icon(
                  onPressed: onGenerateDiary,
                  icon: const Icon(Icons.auto_stories_rounded, size: 18),
                  label: const Text('Trip Diary'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                ),
                // Cancel button — only for Pending bookings
                if (booking.status == 'Pending')
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BookingInfoRow extends StatelessWidget {
  const _BookingInfoRow({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  final IconData icon;
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Trip Diary Bottom Sheet ───────────────────────────────────────────────────

class _TripDiarySheet extends StatefulWidget {
  const _TripDiarySheet({
    required this.destinationName,
    required this.fromDate,
    this.returnDate,
    this.bookingId,
  });

  final String destinationName;
  final String fromDate;
  final String? returnDate;
  final int? bookingId;

  @override
  State<_TripDiarySheet> createState() => _TripDiarySheetState();
}

class _TripDiarySheetState extends State<_TripDiarySheet> {
  final _notesController = TextEditingController();
  bool _isGenerating = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    try {
      await FastApiService().post('/api/diary/trip-diary', {
        'destination_name': widget.destinationName,
        'from_date': widget.fromDate,
        'return_date': widget.returnDate,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'booking_id': widget.bookingId,
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

    String dateText = '';
    final from = DateTime.tryParse(widget.fromDate);
    if (from != null) dateText = df.format(from);
    if (widget.returnDate != null) {
      final ret = DateTime.tryParse(widget.returnDate!);
      if (ret != null) dateText += ' → ${df.format(ret)}';
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24, 20, 24,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
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
                      'AI will write your travel memories',
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
          const SizedBox(height: 18),

          // Trip info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Column(
              children: [
                _SheetInfoRow(
                  icon: Icons.location_on_rounded,
                  label: 'Destination',
                  value: widget.destinationName,
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _SheetInfoRow(
                  icon: Icons.calendar_month_rounded,
                  label: 'Trip Dates',
                  value: dateText.isEmpty ? 'Not specified' : dateText,
                  isDark: isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Notes field
          TextField(
            controller: _notesController,
            maxLines: 3,
            style: TextStyle(
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Any special memories to include? (optional)',
              hintStyle: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                fontSize: 14,
              ),
              filled: true,
              fillColor: isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.primary.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color:
                      isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color:
                      isDark ? AppColors.borderDark : AppColors.borderLight,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
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
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.6),
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
    );
  }
}

class _SheetInfoRow extends StatelessWidget {
  const _SheetInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
