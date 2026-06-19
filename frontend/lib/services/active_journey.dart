import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of the journey the user has currently "started".
///
/// Persisted via SharedPreferences so it survives app restarts. Multiple
/// screens (Start Journey, Alerts, Dashboard) read from this to decide
/// whether to show journey-aware UI.
class ActiveJourneyData {
  final String fromName;
  final double? fromLat;
  final double? fromLon;
  final String toName;
  final double? toLat;
  final double? toLon;
  final String transport;
  final DateTime departureTime;
  /// Route distance in kilometres (from OSRM), null if not yet fetched.
  final double? distanceKm;
  /// Estimated travel time in minutes (from OSRM), null if not yet fetched.
  final int? durationMin;

  const ActiveJourneyData({
    required this.fromName,
    required this.toName,
    required this.transport,
    required this.departureTime,
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
    this.distanceKm,
    this.durationMin,
  });
}

/// Static helper around SharedPreferences for the active journey.
class ActiveJourney {
  static const _kFromName = 'active_journey_from_name';
  static const _kFromLat = 'active_journey_from_lat';
  static const _kFromLon = 'active_journey_from_lon';
  static const _kToName = 'active_journey_to_name';
  static const _kToLat = 'active_journey_to_lat';
  static const _kToLon = 'active_journey_to_lon';
  static const _kTransport = 'active_journey_transport';
  static const _kDepartureTime = 'active_journey_departure_time';
  static const _kDistanceKm = 'active_journey_distance_km';
  static const _kDurationMin = 'active_journey_duration_min';

  /// Save the journey snapshot. Overwrites any previously saved journey.
  static Future<void> save({
    required String fromName,
    required String toName,
    required String transport,
    required DateTime departureTime,
    double? fromLat,
    double? fromLon,
    double? toLat,
    double? toLon,
    double? distanceKm,
    int? durationMin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFromName, fromName);
    await prefs.setString(_kToName, toName);
    await prefs.setString(_kTransport, transport);
    await prefs.setString(_kDepartureTime, departureTime.toIso8601String());

    if (fromLat != null) {
      await prefs.setDouble(_kFromLat, fromLat);
    } else {
      await prefs.remove(_kFromLat);
    }
    if (fromLon != null) {
      await prefs.setDouble(_kFromLon, fromLon);
    } else {
      await prefs.remove(_kFromLon);
    }
    if (toLat != null) {
      await prefs.setDouble(_kToLat, toLat);
    } else {
      await prefs.remove(_kToLat);
    }
    if (toLon != null) {
      await prefs.setDouble(_kToLon, toLon);
    } else {
      await prefs.remove(_kToLon);
    }
    if (distanceKm != null) {
      await prefs.setDouble(_kDistanceKm, distanceKm);
    } else {
      await prefs.remove(_kDistanceKm);
    }
    if (durationMin != null) {
      await prefs.setInt(_kDurationMin, durationMin);
    } else {
      await prefs.remove(_kDurationMin);
    }
  }

  /// Load the saved journey, or null if none is active.
  static Future<ActiveJourneyData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fromName = prefs.getString(_kFromName);
    final toName = prefs.getString(_kToName);
    if (fromName == null || toName == null || toName.trim().isEmpty) {
      return null;
    }
    DateTime departure;
    final rawDeparture = prefs.getString(_kDepartureTime);
    try {
      departure = rawDeparture != null
          ? DateTime.parse(rawDeparture)
          : DateTime.now();
    } catch (_) {
      departure = DateTime.now();
    }
    return ActiveJourneyData(
      fromName: fromName,
      toName: toName,
      transport: prefs.getString(_kTransport) ?? 'car',
      departureTime: departure,
      fromLat: prefs.getDouble(_kFromLat),
      fromLon: prefs.getDouble(_kFromLon),
      toLat: prefs.getDouble(_kToLat),
      toLon: prefs.getDouble(_kToLon),
      distanceKm: prefs.getDouble(_kDistanceKm),
      durationMin: prefs.getInt(_kDurationMin),
    );
  }

  /// True if a journey is currently saved as active.
  static Future<bool> isActive() async {
    final journey = await load();
    return journey != null;
  }

  /// Clear the active journey.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFromName);
    await prefs.remove(_kFromLat);
    await prefs.remove(_kFromLon);
    await prefs.remove(_kToName);
    await prefs.remove(_kToLat);
    await prefs.remove(_kToLon);
    await prefs.remove(_kTransport);
    await prefs.remove(_kDepartureTime);
    await prefs.remove(_kDistanceKm);
    await prefs.remove(_kDurationMin);
  }
}
