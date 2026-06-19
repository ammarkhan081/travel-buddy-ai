import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pakistan_destination.dart';
import '../../models/travel_agency.dart';
import '../../services/booking_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/ui_utils.dart';
import '../../widgets/app_header.dart';
import '../../widgets/destination_image.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, required this.destination});

  final PakistanDestination destination;

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _requestsController = TextEditingController();
  final _dateFormat = DateFormat('dd MMM yyyy');
  final _moneyFormat = NumberFormat.decimalPattern();

  DateTime? _travelDate;
  DateTime? _returnDate;
  int _numPeople = 1;
  TravelAgency? _selectedAgency;

  // Error flags — only shown after a submit attempt, not on load
  bool _showAgencyError = false;
  bool _showTravelDateError = false;
  bool _isSubmitting = false;

  List<TravelAgency> get _agencies {
    final destinationName = widget.destination.name.toLowerCase();
    final province = widget.destination.province.toLowerCase();
    final matches = TravelAgency.mockAgencies.where((agency) {
      return agency.operatingCities.any((city) {
        final value = city.toLowerCase();
        return value.contains(destinationName) ||
            destinationName.contains(value) ||
            value.contains(province) ||
            province.contains(value);
      });
    }).toList();
    // Fallback: show all agencies if none specifically match this destination
    return matches.isEmpty ? TravelAgency.mockAgencies : matches;
  }

  int get _numDays {
    if (_travelDate == null || _returnDate == null) return 1;
    final days = _returnDate!.difference(_travelDate!).inDays;
    return days < 1 ? 1 : days;
  }

  int get _estimatedPrice =>
      widget.destination.pricePerDay * _numPeople * _numDays;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _requestsController.dispose();
    super.dispose();
  }

  Future<void> _pickTravelDate() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: _travelDate ?? tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() {
      _travelDate = picked;
      _showTravelDateError = false;
      // Clear return date if it's no longer after the new travel date
      if (_returnDate != null && !_returnDate!.isAfter(picked)) {
        _returnDate = null;
      }
    });
  }

  Future<void> _pickReturnDate() async {
    final now = DateTime.now();
    final minimum = _travelDate ?? DateTime(now.year, now.month, now.day + 1);
    final firstDate = minimum.add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _returnDate ?? firstDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    setState(() => _returnDate = picked);
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    return null;
  }

  String? _emailValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final text = value?.replaceAll(RegExp(r'[\s-]'), '') ?? '';
    if (text.isEmpty) return 'Required';
    final local = RegExp(r'^03\d{9}$').hasMatch(text);
    final international = RegExp(r'^\+923\d{9}$').hasMatch(text);
    if (!local && !international) {
      return 'Enter a valid Pakistani number (03XXXXXXXXX)';
    }
    return null;
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final agencyMissing = _selectedAgency == null;
    final dateMissing = _travelDate == null;

    setState(() {
      _showAgencyError = agencyMissing;
      _showTravelDateError = dateMissing;
    });

    if (!formValid || agencyMissing || dateMissing) return;

    setState(() => _isSubmitting = true);
    try {
      await BookingService().createBooking(
        destinationName: widget.destination.name,
        agencyId: _selectedAgency!.id,
        agencyName: _selectedAgency!.name,
        travelDate: DateFormat('yyyy-MM-dd').format(_travelDate!),
        returnDate: _returnDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_returnDate!),
        numPeople: _numPeople,
        userPhone: _phoneController.text.trim(),
        userName: _nameController.text.trim(),
        userEmail: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        specialRequests: _requestsController.text.trim().isEmpty
            ? null
            : _requestsController.text.trim(),
      );
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'Booking confirmed! The agency will contact you shortly.',
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showSnackBar(
        context,
        'Could not create booking: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
            title: 'Book a Tour',
            subtitle: widget.destination.name,
            onBack: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  // ── Destination summary ──────────────────────────────────
                  _DestinationSummaryCard(
                    destination: widget.destination,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Your details ─────────────────────────────────────────
                  _SectionHeader(title: 'Your Details', isDark: isDark),
                  const SizedBox(height: 12),
                  _BookingTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    isDark: isDark,
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  _BookingTextField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    isDark: isDark,
                    validator: _phoneValidator,
                  ),
                  const SizedBox(height: 12),
                  _BookingTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    isDark: isDark,
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 24),

                  // ── Trip details ──────────────────────────────────────────
                  _SectionHeader(title: 'Trip Details', isDark: isDark),
                  const SizedBox(height: 12),
                  _DatePickerField(
                    label: 'Travel Date *',
                    value: _travelDate == null
                        ? 'Select travel date'
                        : _dateFormat.format(_travelDate!),
                    icon: Icons.calendar_month,
                    isDark: isDark,
                    hasError: _showTravelDateError,
                    onTap: _pickTravelDate,
                  ),
                  if (_showTravelDateError)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, left: 12),
                      child: Text(
                        'Please select a travel date',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _DatePickerField(
                    label: 'Return Date (optional)',
                    value: _returnDate == null
                        ? 'No return date selected'
                        : _dateFormat.format(_returnDate!),
                    icon: Icons.event_available_outlined,
                    isDark: isDark,
                    onTap: _pickReturnDate,
                  ),
                  const SizedBox(height: 12),
                  _TravelerStepper(
                    value: _numPeople,
                    isDark: isDark,
                    onMinus:
                        _numPeople == 1 ? null : () => setState(() => _numPeople--),
                    onPlus:
                        _numPeople == 20 ? null : () => setState(() => _numPeople++),
                  ),
                  const SizedBox(height: 24),

                  // ── Select agency ─────────────────────────────────────────
                  _SectionHeader(title: 'Select Agency', isDark: isDark),
                  const SizedBox(height: 12),
                  for (final agency in _agencies)
                    _AgencyCard(
                      agency: agency,
                      selected: _selectedAgency?.id == agency.id,
                      isDark: isDark,
                      onTap: () => setState(() {
                        _selectedAgency = agency;
                        _showAgencyError = false;
                      }),
                    ),
                  if (_showAgencyError)
                    const Padding(
                      padding: EdgeInsets.only(top: 2, left: 12),
                      child: Text(
                        'Please select an agency',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // ── Special requests ──────────────────────────────────────
                  _SectionHeader(title: 'Special Requests', isDark: isDark),
                  const SizedBox(height: 12),
                  _BookingTextField(
                    controller: _requestsController,
                    label: 'Any special requirements? (optional)',
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // ── Price estimate ────────────────────────────────────────
                  _SectionHeader(title: 'Price Estimate', isDark: isDark),
                  const SizedBox(height: 12),
                  _PriceCard(
                    amount: 'PKR ${_moneyFormat.format(_estimatedPrice)}',
                    days: _numDays,
                    travelers: _numPeople,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 28),

                  // ── Confirm button ────────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Confirm Booking',
                              style: TextStyle(
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
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _DestinationSummaryCard extends StatelessWidget {
  const _DestinationSummaryCard({
    required this.destination,
    required this.isDark,
  });

  final PakistanDestination destination;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.surfaceDarkElevated : Colors.white;
    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(18)),
            child: DestinationImage(
              destination: destination,
              height: 126,
              width: 124,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    destination.province,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: secondaryText, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        destination.rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: primaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'PKR ${destination.pricePerDay}/day',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.isDark});

  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
    );
  }
}

class _BookingTextField extends StatelessWidget {
  const _BookingTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isDark;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isDark ? AppColors.borderDark : AppColors.borderLight;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor:
            isDark ? AppColors.surfaceDarkElevated : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.danger, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.hasError = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? AppColors.danger
        : isDark
            ? AppColors.borderDark
            : AppColors.borderLight;
    final borderWidth = hasError ? 1.4 : 1.0;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primary),
          filled: true,
          fillColor:
              isDark ? AppColors.surfaceDarkElevated : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: borderColor, width: borderWidth),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: borderColor, width: borderWidth),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TravelerStepper extends StatelessWidget {
  const _TravelerStepper({
    required this.value,
    required this.isDark,
    required this.onMinus,
    required this.onPlus,
  });

  final int value;
  final bool isDark;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Number of Travelers',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: onMinus,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 38,
            child: Center(
              child: Text(
                '$value',
                style: TextStyle(
                  color: textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          IconButton.filled(
            onPressed: onPlus,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _AgencyCard extends StatelessWidget {
  const _AgencyCard({
    required this.agency,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final TravelAgency agency;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? AppColors.primary
              : isDark
                  ? AppColors.borderDark
                  : AppColors.borderLight,
          width: selected ? 2.5 : 1,
        ),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 34),
                    child: Text(
                      agency.name,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star,
                          color: AppColors.warning, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '${agency.rating.toStringAsFixed(1)} (${agency.reviews} reviews)',
                        style: TextStyle(
                          color: secondaryText,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: agency.services.take(3).map((service) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          service,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              if (selected)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.amount,
    required this.days,
    required this.travelers,
    required this.isDark,
  });

  final String amount;
  final int days;
  final int travelers;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? const [] : AppShadows.softCard,
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estimated: $amount',
            style: TextStyle(
              color: primaryText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$days day${days == 1 ? '' : 's'} × $travelers traveler${travelers == 1 ? '' : 's'}',
            style: TextStyle(
              color: secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Final price confirmed by agency. Estimate based on base rate.',
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
