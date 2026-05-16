/// A single user or assistant message inside a [ChatConversation].
class ChatMessage {
  final int id;
  final int conversationId;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  bool get isUser => role == 'user';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    DateTime _parse(dynamic raw) {
      if (raw is String && raw.isNotEmpty) {
        try {
          return DateTime.parse(raw);
        } catch (_) {}
      }
      return DateTime.now();
    }

    return ChatMessage(
      id: (json['id'] as num).toInt(),
      conversationId: (json['conversation_id'] as num).toInt(),
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      createdAt: _parse(json['created_at']),
    );
  }
}
