import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/active_journey.dart';
import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/sun_times.dart';
import '../../widgets/app_header.dart';

/// Alerts module — journey-aware view that surfaces weather, traffic and news
/// for the user's current destination plus a computed travel verdict.
class AlertsModule extends StatefulWidget {
  const AlertsModule({super.key});

  @override
  State<AlertsModule> createState() => _AlertsModuleState();
}

class _AlertsModuleState extends State<AlertsModule> {
  final FastApiService _apiService = FastApiService();

  bool _isLoading = true;
  bool _noJourney = false;
  String? _error;

  // Active journey + resolved labels
  ActiveJourneyData? _journey;
  String _originLabel = 'Current location';
  String _destinationLabel = '—';

  // Destination coords (for sunset). Falls back to current GPS when no journey.
  double? _destLat;
  double? _destLon;

  // Raw response from POST /api/alerts/
  Map<String, dynamic>? _alertsResponse;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────
  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _noJourney = false;
    });

    try {
      _journey = await ActiveJourney.load();

      // Alerts are journey-driven: with no active journey (no chosen
      // destination) we show an empty "decide your destination" state and skip
      // any location/alerts fetching.
      if (_journey == null) {
        if (!mounted) return;
        setState(() {
          _noJourney = true;
          _alertsResponse = null;
          _isLoading = false;
        });
        return;
      }

      String origin = _journey!.fromName;
      String destination = _journey!.toName;
      _destLat = _journey!.toLat;
      _destLon = _journey!.toLon;

      _originLabel = origin;
      _destinationLabel = destination;

      // The default origin label is "Current Location", which the traffic API
      // cannot geocode. Send the real GPS coordinates when we have them so the
      // traffic ETA works; the readable label is kept only for display.
      final originForRequest =
          (_journey!.fromLat != null && _journey!.fromLon != null)
          ? '${_journey!.fromLat},${_journey!.fromLon}'
          : origin;

      final res = await _apiService.post(
        '/api/alerts/',
        {
          'user_id': 'auth',
          'origin': originForRequest,
          'destination': destination,
          'alert_types': const ['weather', 'traffic', 'news'],
        },
        timeout: const Duration(seconds: 30),
      );

      if (!mounted) return;
      setState(() {
        _alertsResponse = res is Map<String, dynamic>
            ? res
            : Map<String, dynamic>.from(res as Map);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _endJourney() async {
    await ActiveJourney.clear();
    if (!mounted) return;
    setState(() => _journey = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Journey ended.')));
    await _bootstrap();
  }

  // ── Derived helpers ────────────────────────────────────────────────────────
  String _riskLabel(double risk) {
    if (risk >= 0.7) return 'High';
    if (risk >= 0.4) return 'Medium';
    return 'Low';
  }

  Color _riskColor(String label) {
    switch (label.toLowerCase()) {
      case 'high':
      case 'critical':
        return AppColors.danger;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  String _aiBriefing() {
    if (_alertsResponse == null) return 'Gathering trip context…';
    final weather = _alertsResponse!['weather'] as Map?;
    final news = _alertsResponse!['news'] as Map?;
    final traffic = _alertsResponse!['traffic'] as Map?;

    final bits = <String>[];
    if (weather != null) {
      final cond = weather['condition'] ?? 'weather';
      final temp = weather['temperature'];
      bits.add(
        'Destination weather: $cond${temp != null ? ' at $temp°C' : ''}.',
      );
    }
    final headlines = (news?['headlines'] as List?) ?? const [];
    if (headlines.isNotEmpty) {
      bits.add('A news/safety update is available for your destination.');
    }
    if (traffic != null) {
      final delay = traffic['estimated_delay'];
      if (delay is num && delay > 0) {
        bits.add('Traffic delay around $delay min on the route.');
      }
    }
    if (bits.isEmpty) {
      return 'No major issues detected for your destination right now.';
    }
    return bits.join(' ');
  }

  String _bestDeparture() {
    final traffic = _alertsResponse?['traffic'] as Map?;
    final delay = traffic?['estimated_delay'];
    final now = DateTime.now();
    final base = (delay is num && delay > 10)
        ? now.add(const Duration(minutes: 30))
        : now;
    final h = base.hour > 12
        ? base.hour - 12
        : (base.hour == 0 ? 12 : base.hour);
    final m = base.minute.toString().padLeft(2, '0');
    final ampm = base.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  int _activeAlertCount() {
    if (_alertsResponse == null) return 0;
    int count = 0;
    final weather = _alertsResponse!['weather'] as Map?;
    if (weather != null) count++;
    final news = _alertsResponse!['news'] as Map?;
    final headlines = (news?['headlines'] as List?) ?? const [];
    count += headlines.length.clamp(0, 2).toInt();
    final traffic = _alertsResponse!['traffic'] as Map?;
    if (traffic != null && (traffic['estimated_delay'] is num)) {
      final delay = traffic['estimated_delay'] as num;
      if (delay > 0) count++;
    }
    return count;
  }

  String? _approxDistance() {
    final from = _journey;
    if (from == null ||
        from.fromLat == null ||
        from.fromLon == null ||
        from.toLat == null ||
        from.toLon == null) {
      final t = _alertsResponse?['traffic'] as Map?;
      final txt = t?['distance_text'];
      if (txt is String && txt.isNotEmpty) return txt;
      return null;
    }
    final km = _haversineKm(
      from.fromLat!,
      from.fromLon!,
      from.toLat!,
      from.toLon!,
    );
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  String? _eta() {
    final t = _alertsResponse?['traffic'] as Map?;
    final txt = t?['duration_in_traffic_text'] ?? t?['duration_text'];
    if (txt is String && txt.isNotEmpty) return txt;
    return null;
  }

  int? _parseDurationToMinutes(String? text) {
    if (text == null || text.isEmpty) return null;
    int total = 0;
    final hoursMatch = RegExp(r'(\d+)\s*hour').firstMatch(text);
    if (hoursMatch != null) {
      total += int.parse(hoursMatch.group(1)!) * 60;
    }
    final minsMatch = RegExp(r'(\d+)\s*min').firstMatch(text);
    if (minsMatch != null) {
      total += int.parse(minsMatch.group(1)!);
    }
    return total > 0 ? total : null;
  }

  DateTime? _arrivalTime() {
    final t = _alertsResponse?['traffic'] as Map?;
    final txt =
        t?['duration_in_traffic_text'] as String? ??
        t?['duration_text'] as String?;
    final minutes = _parseDurationToMinutes(txt);
    if (minutes == null) return null;
    return DateTime.now().add(Duration(minutes: minutes));
  }

  DateTime? _sunsetAtDestination() {
    if (_destLat == null || _destLon == null) return null;
    return SunTimes.sunsetFor(
      date: DateTime.now(),
      lat: _destLat!,
      lon: _destLon!,
    );
  }

  String _formatClock(DateTime dt) {
    final h12 = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h12:$m $ampm';
  }

  _JourneyVerdict _computeVerdict() {
    final resp = _alertsResponse ?? const {};
    final weather = resp['weather'] as Map?;
    final traffic = resp['traffic'] as Map?;
    final news = resp['news'] as Map?;
    final headlines = (news?['headlines'] as List?) ?? const [];

    int score = 0;
    final reasons = <String>[];

    final weatherRisk = (weather?['risk_level'] ?? 'low')
        .toString()
        .toLowerCase();
    if (weatherRisk == 'high' || weatherRisk == 'critical') {
      score += 3;
      final cond = (weather?['condition'] ?? 'severe weather').toString();
      reasons.add('$cond at destination');
    } else if (weatherRisk == 'medium') {
      score += 1;
    }

    final delay = traffic?['estimated_delay'];
    if (delay is num && delay >= 30) {
      score += 2;
      reasons.add('Heavy traffic (~${delay.toInt()} min slower)');
    } else if (delay is num && delay >= 10) {
      score += 1;
    }

    const unsafeKeywords = [
      'protest',
      'closure',
      'closed',
      'curfew',
      'attack',
      'blast',
      'riot',
      'accident',
      'blockade',
      'blocked',
      'killed',
      'unrest',
      'violence',
      'strike',
      'shutdown',
      'flood',
      'landslide',
    ];
    int safetyHits = 0;
    for (final h in headlines) {
      final lower = h.toString().toLowerCase();
      if (unsafeKeywords.any((kw) => lower.contains(kw))) {
        safetyHits++;
      }
    }
    if (safetyHits > 0) {
      score += safetyHits * 2;
      reasons.add(
        '$safetyHits safety news item${safetyHits > 1 ? 's' : ''} at destination',
      );
    }

    final arrival = _arrivalTime();
    final sunset = _sunsetAtDestination();
    if (arrival != null && sunset != null && arrival.isAfter(sunset)) {
      final minsPast = arrival.difference(sunset).inMinutes;
      score += 2;
      reasons.add('Arrives ~$minsPast min after sunset');
    }

    String label;
    Color color;
    IconData icon;
    String tagline;
    if (score >= 6) {
      label = 'CONSIDER POSTPONING';
      color = AppColors.danger;
      icon = Icons.do_not_disturb_on_outlined;
      tagline = 'Multiple risks detected on this route.';
    } else if (score >= 3) {
      label = 'TRAVEL WITH CAUTION';
      color = AppColors.warning;
      icon = Icons.warning_amber_rounded;
      tagline = 'Manageable risks — plan carefully and stay alert.';
    } else {
      label = 'SAFE TO GO';
      color = AppColors.success;
      icon = Icons.check_circle_outline;
      tagline = 'No significant issues for this trip right now.';
    }

    if (reasons.isEmpty) {
      reasons.add('No major risk signals detected');
    }

    return _JourneyVerdict(
      label: label,
      tagline: tagline,
      color: color,
      icon: icon,
      reasons: reasons.take(3).toList(),
    );
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double toRad(double d) => d * (math.pi / 180.0);
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final journeyActive = _journey != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'Alerts',
            subtitle: journeyActive
                ? 'Live updates for your active journey'
                : 'Start a journey to see destination alerts',
            onBack: () => Navigator.maybePop(context),
            actions: [
              if (journeyActive)
                AppHeaderIconButton(
                  icon: Icons.stop_circle_outlined,
                  onTap: _endJourney,
                ),
              AppHeaderIconButton(icon: Icons.refresh, onTap: _bootstrap),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _buildErrorState()
                : _noJourney
                ? _buildNoJourneyState()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppEmptyState(
          icon: Icons.error_outline,
          title: 'Couldn\'t load alerts',
          subtitle: _error ?? 'Please try again in a moment.',
          ctaLabel: 'Retry',
          onCta: _bootstrap,
        ),
      ),
    );
  }

  Widget _buildNoJourneyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AppEmptyState(
          icon: Icons.explore_off_outlined,
          title: 'No destination selected',
          subtitle:
              'Start a journey and choose your destination to see live weather, traffic and safety alerts for that trip.',
          ctaLabel: 'Start a journey',
          onCta: () => Navigator.of(context).pushNamed('/startJourney'),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final resp = _alertsResponse ?? const <String, dynamic>{};
    final risk = (resp['overall_risk_score'] is num)
        ? (resp['overall_risk_score'] as num).toDouble()
        : 0.0;
    final riskLabel = _riskLabel(risk);
    final weather = resp['weather'] as Map?;
    final news = resp['news'] as Map?;
    final headlines = (news?['headlines'] as List?) ?? const [];
    final traffic = resp['traffic'] as Map?;
    final verdict = _computeVerdict();

    return RefreshIndicator(
      onRefresh: _bootstrap,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _buildVerdictCard(verdict),
          const SizedBox(height: 16),
          _buildJourneyHeaderCard(riskLabel),
          const SizedBox(height: 20),
          AppSectionTitle(title: 'AI Summary', icon: Icons.auto_awesome),
          const SizedBox(height: 10),
          _buildAiBriefingCard(riskLabel),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: AppSectionTitle(
                  title: 'Active Alerts',
                  icon: Icons.notifications_active_rounded,
                ),
              ),
              _countPill(_activeAlertCount()),
            ],
          ),
          const SizedBox(height: 10),
          if (weather != null) _buildWeatherAlertTile(weather),
          for (final h in headlines.take(2)) _buildNewsAlertTile(h.toString()),
          if (traffic != null &&
              (traffic['estimated_delay'] is num) &&
              (traffic['estimated_delay'] as num) > 0)
            _buildTrafficAlertTile(traffic),
          if (weather == null && headlines.isEmpty) _buildEmptyAlertsCard(),
          if (weather != null) ...[
            const SizedBox(height: 20),
            AppSectionTitle(
              title: 'Weather · Destination',
              icon: Icons.thermostat_rounded,
            ),
            const SizedBox(height: 10),
            _buildWeatherDetailCard(weather),
          ],
        ],
      ),
    );
  }

  Widget _countPill(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: count > 0
            ? AppColors.warning.withValues(alpha: 0.15)
            : AppColors.success.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count active',
        style: TextStyle(
          color: count > 0 ? AppColors.warning : AppColors.success,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  // ── Verdict card ───────────────────────────────────────────────────────────
  Widget _buildVerdictCard(_JourneyVerdict v) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            v.color.withValues(alpha: isDark ? 0.25 : 0.18),
            v.color.withValues(alpha: isDark ? 0.10 : 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: v.color.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: v.color.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(v.icon, color: v.color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.label,
                      style: TextStyle(
                        color: v.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      v.tagline,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.08,
            ),
            height: 1,
          ),
          const SizedBox(height: 12),
          for (final r in v.reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.fiber_manual_record, size: 8, color: v.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Journey header card ────────────────────────────────────────────────────
  Widget _buildJourneyHeaderCard(String riskLabel) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final distance = _approxDistance();
    final eta = _eta();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // From row
          Row(
            children: [
              const Icon(Icons.my_location, color: AppColors.success, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _originLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              _journey != null ? 'Origin' : 'Current location',
              style: TextStyle(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
          // dotted connector
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const SizedBox(width: 9),
                Container(
                  width: 0,
                  height: 18,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.18),
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Destination
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _destinationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 2),
            child: Text(
              'Destination',
              style: TextStyle(
                color: isDark
                    ? AppColors.textTertiaryDark
                    : AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statTile('ETA', eta ?? '—')),
              const SizedBox(width: 10),
              Expanded(child: _statTile('Distance', distance ?? '—')),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  'Risk',
                  riskLabel,
                  valueColor: _riskColor(riskLabel),
                  highlight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSunsetRow(),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Realtime',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSunsetRow() {
    final sunset = _sunsetAtDestination();
    final arrival = _arrivalTime();
    if (sunset == null && arrival == null) return const SizedBox.shrink();

    final sunsetStr = sunset != null ? _formatClock(sunset) : '—';
    final arrivalStr = arrival != null ? _formatClock(arrival) : null;

    bool arrivesAfterDark = false;
    int minsPastSunset = 0;
    if (sunset != null && arrival != null && arrival.isAfter(sunset)) {
      arrivesAfterDark = true;
      minsPastSunset = arrival.difference(sunset).inMinutes;
    }

    final warnColor = arrivesAfterDark ? AppColors.warning : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            arrivesAfterDark ? Icons.nights_stay_outlined : Icons.wb_twilight,
            size: 16,
            color: warnColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              arrivalStr != null
                  ? (arrivesAfterDark
                        ? 'ETA $arrivalStr · arrives ~$minsPastSunset min after sunset ($sunsetStr)'
                        : 'ETA $arrivalStr · sunset at destination $sunsetStr')
                  : 'Sunset at destination $sunsetStr',
              style: TextStyle(
                color: warnColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(
    String label,
    String value, {
    Color? valueColor,
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = valueColor ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: highlight
            ? color.withValues(alpha: 0.10)
            : (isDark ? AppColors.surfaceDarkElevated : AppColors.headerLilac),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: highlight
            ? Border.all(color: color.withValues(alpha: 0.45), width: 1.2)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color:
                  valueColor ??
                  (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildAiBriefingCard(String riskLabel) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final detected = _activeAlertCount();
    return Container(
      padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'AI Briefing',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Best departure: ${_bestDeparture()}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _aiBriefing(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: _riskColor(riskLabel),
                ),
                const SizedBox(width: 6),
                Text(
                  'Risk: $riskLabel',
                  style: TextStyle(
                    color: _riskColor(riskLabel),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '$detected detected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (isDark) const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _alertBaseTile({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required String type,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _typeChip(type, accent),
        ],
      ),
    );
  }

  Widget _buildWeatherAlertTile(Map weather) {
    final cond = (weather['condition'] ?? 'Weather').toString();
    final desc = (weather['description'] ?? '').toString();
    final temp = weather['temperature'];
    return _alertBaseTile(
      icon: Icons.cloud_outlined,
      accent: AppColors.infoBlue,
      title: '$cond expected',
      subtitle: '${temp != null ? '$temp°C · ' : ''}$desc',
      type: 'WEATHER',
    );
  }

  Widget _buildNewsAlertTile(String headline) {
    return _alertBaseTile(
      icon: Icons.article_outlined,
      accent: AppColors.primary,
      title: 'News & Safety',
      subtitle: headline,
      type: 'NEWS',
    );
  }

  Widget _buildTrafficAlertTile(Map traffic) {
    final delay = traffic['estimated_delay'];
    return _alertBaseTile(
      icon: Icons.traffic_rounded,
      accent: AppColors.warning,
      title: 'Traffic delay',
      subtitle: 'Around $delay min slower than usual on this route.',
      type: 'TRAFFIC',
    );
  }

  Widget _buildEmptyAlertsCard() {
    return AppEmptyState(
      icon: Icons.check_circle_outline,
      title: 'No major alerts',
      subtitle: 'You\'re good to go — weather, traffic and news look calm.',
    );
  }

  Widget _buildWeatherDetailCard(Map weather) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final temp = weather['temperature'];
    final cond = (weather['condition'] ?? 'Clear').toString();
    final humidity = weather['humidity'];
    final wind = weather['wind_speed_kmh'];
    final visibility = weather['visibility_km'];
    final location = (weather['location'] ?? _destinationLabel).toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: isDark ? const [] : AppShadows.softCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Icon(
                  Icons.wb_sunny,
                  color: AppColors.warning,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      temp != null ? '${temp.toString()}°C' : '—',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 28,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cond,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (humidity != null)
                _weatherBadge(Icons.water_drop, 'Humidity $humidity%'),
              if (wind != null)
                _weatherBadge(Icons.air, 'Wind ${wind.toString()} km/h'),
              if (visibility != null)
                _weatherBadge(
                  Icons.visibility,
                  'Visibility ${visibility.toString()} km',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weatherBadge(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _JourneyVerdict {
  final String label;
  final String tagline;
  final Color color;
  final IconData icon;
  final List<String> reasons;

  const _JourneyVerdict({
    required this.label,
    required this.tagline,
    required this.color,
    required this.icon,
    required this.reasons,
  });
}
