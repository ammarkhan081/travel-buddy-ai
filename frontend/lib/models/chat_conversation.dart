/// A chat thread between the user and Travel Buddy AI.
class ChatConversation {
  final int id;
  final String title;
  final String? lastLocation;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatConversation({
    required this.id,
    required this.title,
    this.lastLocation,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    DateTime _parse(dynamic raw) {
      if (raw is String && raw.isNotEmpty) {
        try {
          return DateTime.parse(raw);
        } catch (_) {}
      }
      return DateTime.now();
    }

    return ChatConversation(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : 'New Chat',
      lastLocation: json['last_location'] as String?,
      createdAt: _parse(json['created_at']),
      updatedAt: _parse(json['updated_at']),
    );
  }

  ChatConversation copyWith({
    int? id,
    String? title,
    String? lastLocation,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      lastLocation: lastLocation ?? this.lastLocation,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
