class BookingModel {
  final int id;
  final String userId;
  final String destinationName;
  final String agencyId;
  final String agencyName;
  final String travelDate;
  final String? returnDate;
  final int numPeople;
  final String userPhone;
  final String userName;
  final String? userEmail;
  final String? specialRequests;
  final String status;
  final String createdAt;

  const BookingModel({
    required this.id,
    required this.userId,
    required this.destinationName,
    required this.agencyId,
    required this.agencyName,
    required this.travelDate,
    this.returnDate,
    required this.numPeople,
    required this.userPhone,
    required this.userName,
    this.userEmail,
    this.specialRequests,
    required this.status,
    required this.createdAt,
  });

  factory BookingModel.fromJson(Map<String, dynamic> json) => BookingModel(
    id: json['id'] as int,
    userId: json['user_id'] as String,
    destinationName: json['destination_name'] as String,
    agencyId: json['agency_id'] as String,
    agencyName: json['agency_name'] as String,
    travelDate: json['travel_date'] as String,
    returnDate: json['return_date'] as String?,
    numPeople: json['num_people'] as int,
    userPhone: json['user_phone'] as String,
    userName: json['user_name'] as String,
    userEmail: json['user_email'] as String?,
    specialRequests: json['special_requests'] as String?,
    status: json['status'] as String,
    createdAt: json['created_at'] as String,
  );

  Map<String, dynamic> toJson() => {
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
}
