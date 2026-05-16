import 'package:cloud_firestore/cloud_firestore.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String relation;
  final String userId;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
    required this.userId,
  });

  factory EmergencyContact.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EmergencyContact(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      relation: data['relation'] ?? '',
      userId: data['userId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'phone': phone,
        'relation': relation,
        'userId': userId,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
