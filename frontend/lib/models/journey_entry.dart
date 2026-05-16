import 'package:cloud_firestore/cloud_firestore.dart';

class JourneyEntry {
  final String id;
  final String fromPlace;
  final String toPlace;
  final DateTime departureTime;
  final DateTime? arrivalTime;
  final String transport;
  final List<String> foodItems;
  final String notes;
  final bool isCompleted;
  final String userId;

  const JourneyEntry({
    required this.id,
    required this.fromPlace,
    required this.toPlace,
    required this.departureTime,
    this.arrivalTime,
    required this.transport,
    required this.foodItems,
    required this.notes,
    required this.isCompleted,
    required this.userId,
  });

  factory JourneyEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JourneyEntry(
      id: doc.id,
      fromPlace: data['fromPlace'] ?? '',
      toPlace: data['toPlace'] ?? '',
      departureTime: (data['departureTime'] as Timestamp).toDate(),
      arrivalTime: data['arrivalTime'] != null
          ? (data['arrivalTime'] as Timestamp).toDate()
          : null,
      transport: data['transport'] ?? 'car',
      foodItems: List<String>.from(data['foodItems'] ?? []),
      notes: data['notes'] ?? '',
      isCompleted: data['isCompleted'] ?? false,
      userId: data['userId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fromPlace': fromPlace,
        'toPlace': toPlace,
        'departureTime': Timestamp.fromDate(departureTime),
        'arrivalTime':
            arrivalTime != null ? Timestamp.fromDate(arrivalTime!) : null,
        'transport': transport,
        'foodItems': foodItems,
        'notes': notes,
        'isCompleted': isCompleted,
        'userId': userId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  JourneyEntry copyWith({
    String? fromPlace,
    String? toPlace,
    DateTime? departureTime,
    DateTime? arrivalTime,
    String? transport,
    List<String>? foodItems,
    String? notes,
    bool? isCompleted,
  }) =>
      JourneyEntry(
        id: id,
        fromPlace: fromPlace ?? this.fromPlace,
        toPlace: toPlace ?? this.toPlace,
        departureTime: departureTime ?? this.departureTime,
        arrivalTime: arrivalTime ?? this.arrivalTime,
        transport: transport ?? this.transport,
        foodItems: foodItems ?? this.foodItems,
        notes: notes ?? this.notes,
        isCompleted: isCompleted ?? this.isCompleted,
        userId: userId,
      );
}
