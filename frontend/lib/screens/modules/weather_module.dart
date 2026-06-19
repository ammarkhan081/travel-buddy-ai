import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../services/active_journey.dart';
import '../../services/fastapi_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_header.dart';

/// Weather module — detailed weather view for user's current location or destination.
///
/// Displays comprehensive weather information including temperature, conditions,
/// humidity, wind speed, visibility, and hourly forecast.
class WeatherModule extends StatefulWidget {
  const WeatherModule({super.key});

  @override
  State<WeatherModule> createState() => _WeatherModuleState();
}

class _WeatherModuleState extends State<WeatherModule> {
  final FastApiService _apiService = FastApiService();

  bool _isLoading = true;
  String? _error;

  // Active journey + resolved labels
  ActiveJourneyData? _journey;
  String _locationLabel = 'Current location';

  // Raw weather data
  Map<String, dynamic>? _weatherData;

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
    });

    try {
      _journey = await ActiveJourney.load();

      String location = 'Current location';
      double? lat;
      double? lon;

      if (_journey != null) {
        location = _journey!.toName;
        lat = _journey!.toLat;
        lon = _journey!.toLon;
      } else {
        final pos = await _fetchLocationSafely();
        if (pos != null) {
          final label = await _reverseGeocode(pos.latitude, pos.longitude);
          location = label;
          lat = pos.latitude;
          lon = pos.longitude;
        } else {
          location = 'Lahore, Pakistan';
          lat = 31.5204;
          lon = 74.3587;
        }
      }

      _locationLabel = location;

      // Fetch weather data using coordinates
      final res = await _apiService.post('/api/weather/', {
        'latitude': lat,
        'longitude': lon,
        'location': location,
      });

      if (!mounted) return;
      setState(() {
        _weatherData = res is Map<String, dynamic>
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

  Future<Position?> _fetchLocationSafely() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
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

  Future<String> _reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json',
      );
      final res = await http
          .get(uri, headers: {'Accept-Language': 'en'})
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final name = (data['display_name'] ?? '').toString();
        if (name.isNotEmpty) {
          return name.split(',').take(2).join(', ');
        }
      }
    } catch (_) {}
    return 'Unknown';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AppHeader(
            title: 'Weather',
            subtitle: _locationLabel,
            onBack: () => Navigator.maybePop(context),
            actions: [
              AppHeaderIconButton(icon: Icons.refresh, onTap: _bootstrap),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.danger,
            ),
            const SizedBox(height: 16),
            const Text(
              'Couldn\'t load weather',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Please try again in a moment.',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _bootstrap,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_weatherData == null) {
      return const Center(
        child: Text('No weather data available'),
      );
    }

    return RefreshIndicator(
      onRefresh: _bootstrap,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _buildCurrentWeatherCard(),
          const SizedBox(height: 20),
          _buildWeatherDetailsCard(),
          const SizedBox(height: 20),
          _buildHourlyForecastCard(),
          const SizedBox(height: 20),
          _buildWeatherDescriptionCard(),
        ],
      ),
    );
  }

  Widget _buildCurrentWeatherCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final temp = _weatherData?['temperature'];
    final condition = (_weatherData?['condition'] ?? 'N/A').toString();
    final riskLevel = (_weatherData?['risk_level'] ?? 'low').toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.18),
            AppColors.primary.withValues(alpha: isDark ? 0.10 : 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.55),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    temp != null ? '${temp.toString()}°C' : '—',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 48,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    condition,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.wb_sunny,
                  color: AppColors.warning,
                  size: 48,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _riskLevelColor(riskLevel).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Risk Level: ${riskLevel.toUpperCase()}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: _riskLevelColor(riskLevel),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherDetailsCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final humidity = _weatherData?['humidity'];
    final wind = _weatherData?['wind_speed_kmh'];
    final visibility = _weatherData?['visibility_km'];
    final feelsLike = _weatherData?['feels_like'];
    final pressure = _weatherData?['pressure_mb'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? const [] : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Conditions',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              if (feelsLike != null)
                _weatherDetailBadge(
                  Icons.thermostat,
                  'Feels Like',
                  '${feelsLike.toString()}°C',
                ),
              if (humidity != null)
                _weatherDetailBadge(
                  Icons.water_drop,
                  'Humidity',
                  '$humidity%',
                ),
              if (wind != null)
                _weatherDetailBadge(
                  Icons.air,
                  'Wind Speed',
                  '${wind.toString()} km/h',
                ),
              if (visibility != null)
                _weatherDetailBadge(
                  Icons.visibility,
                  'Visibility',
                  '${visibility.toString()} km',
                ),
              if (pressure != null)
                _weatherDetailBadge(
                  Icons.compress,
                  'Pressure',
                  '${pressure.toString()} mb',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyForecastCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hourlyData = (_weatherData?['hourly_forecast'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        const <Map<String, dynamic>>[];

    if (hourlyData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? const [] : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hourly Forecast',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(
                (hourlyData.length).clamp(0, 12),
                (index) {
                  final hour = hourlyData[index];
                  final temp = hour['temperature'];
                  final time = _formatHourlyTime(index);

                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              AppColors.primary.withValues(alpha: 0.20),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Icon(
                            Icons.cloud,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            temp != null ? '${temp.toString()}°' : '—',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherDescriptionCard() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final description =
        (_weatherData?['description'] ?? 'No description available')
            .toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? const [] : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weatherDetailBadge(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.20),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatHourlyTime(int index) {
    final now = DateTime.now();
    final time = now.add(Duration(hours: index));
    final hour = time.hour;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour $ampm';
  }

  Color _riskLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
      case 'high':
        return AppColors.danger;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }
}

