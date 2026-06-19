import 'dart:math' as math;

/// Sunset / sunrise calculator (pure math — no external API).
///
/// Based on the simplified NOAA solar position algorithm. Accurate to roughly
/// ±1 minute, which is good enough for "will I arrive before dark?" checks.
///
/// Usage:
///   final ss = SunTimes.sunsetFor(date: DateTime.now(), lat: 31.5, lon: 74.3);
///   // -> DateTime in the device's local timezone
class SunTimes {
  /// Compute local sunset for the given date and location.
  /// Returns null at extreme latitudes / dates where the sun never sets or rises.
  static DateTime? sunsetFor({
    required DateTime date,
    required double lat,
    required double lon,
  }) =>
      _solarEventLocal(date: date, lat: lat, lon: lon, sunrise: false);

  /// Compute local sunrise for the given date and location.
  static DateTime? sunriseFor({
    required DateTime date,
    required double lat,
    required double lon,
  }) =>
      _solarEventLocal(date: date, lat: lat, lon: lon, sunrise: true);

  // ── Internal ────────────────────────────────────────────────────────────────

  static DateTime? _solarEventLocal({
    required DateTime date,
    required double lat,
    required double lon,
    required bool sunrise,
  }) {
    final n = _dayOfYear(date);
    final lonHour = lon / 15.0;
    final t = sunrise
        ? n + ((6.0 - lonHour) / 24.0)
        : n + ((18.0 - lonHour) / 24.0);

    // Sun's mean anomaly
    final m = (0.9856 * t) - 3.289;

    // Sun's true longitude
    double l = m +
        (1.916 * math.sin(_deg2rad(m))) +
        (0.020 * math.sin(_deg2rad(2 * m))) +
        282.634;
    l = _normalize(l, 360);

    // Sun's right ascension
    double ra = _rad2deg(math.atan(0.91764 * math.tan(_deg2rad(l))));
    ra = _normalize(ra, 360);

    // Adjust RA to same quadrant as L
    final lQuadrant = (l / 90.0).floor() * 90.0;
    final raQuadrant = (ra / 90.0).floor() * 90.0;
    ra = ra + (lQuadrant - raQuadrant);

    ra = ra / 15.0; // to hours

    // Sun's declination
    final sinDec = 0.39782 * math.sin(_deg2rad(l));
    final cosDec = math.cos(math.asin(sinDec));

    // Sun's local hour angle
    const zenith = 90.833; // official sunrise/sunset
    final cosH = (math.cos(_deg2rad(zenith)) -
            (sinDec * math.sin(_deg2rad(lat)))) /
        (cosDec * math.cos(_deg2rad(lat)));
    if (cosH > 1 || cosH < -1) {
      return null; // sun never rises / sets at this latitude on this date
    }

    double h;
    if (sunrise) {
      h = 360.0 - _rad2deg(math.acos(cosH));
    } else {
      h = _rad2deg(math.acos(cosH));
    }
    h = h / 15.0; // to hours

    // Local mean time of event
    final t2 = h + ra - (0.06571 * t) - 6.622;

    // UTC time
    double utc = t2 - lonHour;
    utc = _normalize(utc, 24);

    // Local time (device timezone)
    final tzOffsetHours = DateTime.now().timeZoneOffset.inMinutes / 60.0;
    double localTime = utc + tzOffsetHours;
    localTime = _normalize(localTime, 24);

    final hours = localTime.floor();
    final minutes = ((localTime - hours) * 60.0).round();
    final safeMinutes = minutes.clamp(0, 59);

    return DateTime(
      date.year,
      date.month,
      date.day,
      hours,
      safeMinutes,
    );
  }

  static int _dayOfYear(DateTime date) =>
      date.difference(DateTime(date.year, 1, 1)).inDays + 1;

  static double _deg2rad(double d) => d * math.pi / 180.0;

  static double _rad2deg(double r) => r * 180.0 / math.pi;

  static double _normalize(double v, double max) {
    double r = v;
    while (r < 0) {
      r += max;
    }
    while (r >= max) {
      r -= max;
    }
    return r;
  }
}
