import 'fastapi_service.dart';

/// Thin client for the backend Trip API.
///
/// A "trip" is the first-class container that scopes a user's expenses,
/// reminders, voice notes and diary entries. Starting a trip here makes the
/// backend auto-tag every new record created while it is active, so the
/// chatbot can later answer per-trip questions (e.g. "my expenses on the
/// Kalam trip"). All calls are best-effort and never throw, so the existing
/// journey UI keeps working even if the backend is unreachable.
class TripApiService {
  static final TripApiService _instance = TripApiService._internal();
  factory TripApiService() => _instance;
  TripApiService._internal();

  final FastApiService _api = FastApiService();

  /// Start (or record) a trip on the backend. Returns the new trip id, or null.
  Future<int?> startTrip({
    required String destination,
    String? origin,
    String? transport,
  }) async {
    try {
      final body = <String, dynamic>{'destination': destination};
      if (origin != null && origin.trim().isNotEmpty) body['origin'] = origin;
      if (transport != null && transport.trim().isNotEmpty) {
        body['transport'] = transport;
      }
      final res = await _api.post('/api/trips/', body);
      if (res is Map && res['id'] != null) {
        return (res['id'] as num).toInt();
      }
    } catch (_) {
      // Best-effort: ignore failures so the journey still starts locally.
    }
    return null;
  }

  /// Return the currently active trip (or null if none / on error).
  Future<Map<String, dynamic>?> getActiveTrip() async {
    try {
      final res = await _api.get('/api/trips/active');
      if (res is Map && res['id'] != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return null;
  }

  /// Mark the active trip completed (e.g. on arrival / end-journey).
  Future<void> completeActiveTrip() async {
    try {
      final active = await getActiveTrip();
      final id = (active != null && active['id'] != null)
          ? (active['id'] as num).toInt()
          : null;
      if (id != null) {
        await _api.patch('/api/trips/$id/status', {'status': 'completed'});
      }
    } catch (_) {}
  }

  /// List all of the user's trips (newest first). Empty list on error.
  Future<List<dynamic>> listTrips() async {
    try {
      final res = await _api.get('/api/trips/');
      if (res is List) return res;
    } catch (_) {}
    return const [];
  }
}
