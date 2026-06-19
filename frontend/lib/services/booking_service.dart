import '../models/booking.dart';
import 'fastapi_service.dart';

class BookingService {
  static final BookingService _instance = BookingService._internal();
  factory BookingService() => _instance;
  BookingService._internal();

  final FastApiService _api = FastApiService();

  Future<List<BookingModel>> getMyBookings() async {
    final data = await _api.get('/api/bookings/');
    return (data as List)
        .map((e) => BookingModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<BookingModel> createBooking({
    required String destinationName,
    required String agencyId,
    required String agencyName,
    required String travelDate,
    String? returnDate,
    required int numPeople,
    required String userPhone,
    required String userName,
    String? userEmail,
    String? specialRequests,
  }) async {
    final body = {
      'destination_name': destinationName,
      'agency_id': agencyId,
      'agency_name': agencyName,
      'travel_date': travelDate,
      'return_date': returnDate,
      'num_people': numPeople,
      'user_phone': userPhone,
      'user_name': userName,
      'user_email': userEmail,
      'special_requests': specialRequests,
    };
    final data = await _api.post('/api/bookings/', body);
    return BookingModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<BookingModel> cancelBooking(int bookingId) async {
    final data = await _api.patch('/api/bookings/$bookingId/cancel', {});
    return BookingModel.fromJson(Map<String, dynamic>.from(data));
  }
}
