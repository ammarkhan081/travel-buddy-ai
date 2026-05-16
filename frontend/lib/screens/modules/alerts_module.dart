import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/fastapi_service.dart';

class AlertsModule extends StatefulWidget {
  const AlertsModule({super.key});

  @override
  State<AlertsModule> createState() => _AlertsModuleState();
}

class _AlertsModuleState extends State<AlertsModule> {
  final FastApiService _apiService = FastApiService();
  List<dynamic> _alerts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  /// Attempts to fetch the device's current GPS position.
  /// Returns null silently on any failure (permission denied, GPS off, timeout)
  /// so the alerts fetch continues without crashing.
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

  Future<void> _fetchAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Try to get real device coordinates first.
      final position = await _fetchLocationSafely();

      final Map<String, String> params;
      if (position != null) {
        // Prefer lat/lon — backend reverse-geocodes for weather & news.
        params = {
          'lat': position.latitude.toString(),
          'lon': position.longitude.toString(),
        };
      } else {
        // GPS unavailable — fall back to named location.
        params = {'location': 'Islamabad'};
      }

      final data = await _apiService.get('/api/alerts/', queryParams: params);

      if (mounted) {
        setState(() {
          _alerts = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        backgroundColor: const Color(0xFF1E66F5),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAlerts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Failed to load alerts: $_error', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchAlerts,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _alerts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text('No active alerts at the moment', style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _alerts.length,
                      itemBuilder: (context, index) {
                        final alert = _alerts[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: _buildAlertCard(
                            context,
                            icon: _getIconForType(alert['type']),
                            title: _getTitleForType(alert['type']),
                            description: alert['message'] ?? '',
                            time: 'Just now',
                            color: _getColorForSeverity(alert['severity']),
                          ),
                        );
                      },
                    ),
    );
  }

  IconData _getIconForType(String? type) {
    switch (type) {
      case 'weather':
        return Icons.wb_sunny;
      case 'traffic':
        return Icons.traffic;
      case 'news':
        return Icons.newspaper;
      default:
        return Icons.notifications;
    }
  }

  String _getTitleForType(String? type) {
    if (type == null) return "Alert";
    return "${type[0].toUpperCase()}${type.substring(1)} Alert";
  }

  Color _getColorForSeverity(String? severity) {
    switch (severity) {
      case 'critical':
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  Widget _buildAlertCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String time,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.bold,
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
      ),
    );
  }
}

