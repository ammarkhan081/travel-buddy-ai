import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import 'fastapi_service.dart';

/// Thin wrapper around the backend's `/api/chat` conversation endpoints.
///
/// The legacy `/api/chat/reply` route is still used by `ai_chat_service.dart`
/// (for the Gemini-only path); this repository targets the new conversation-
/// scoped endpoints so we can support ChatGPT-style history and titles.
class ChatRepository {
  ChatRepository({FastApiService? api}) : _api = api ?? FastApiService();

  final FastApiService _api;

  /// Sidebar list — most recently updated first.
  Future<List<ChatConversation>> listConversations() async {
    final raw = await _api.get('/api/chat/conversations');
    if (raw is! List) return <ChatConversation>[];
    return raw
        .map((j) => ChatConversation.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList(growable: true);
  }

  /// Create a new empty conversation. Title auto-fills on the first message.
  Future<ChatConversation> createConversation() async {
    final raw = await _api.post('/api/chat/conversations', const {});
    return ChatConversation.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// All messages in a conversation, chronological order.
  Future<List<ChatMessage>> getMessages(int conversationId) async {
    final raw = await _api.get('/api/chat/conversations/$conversationId/messages');
    if (raw is! List) return <ChatMessage>[];
    return raw
        .map((j) => ChatMessage.fromJson(Map<String, dynamic>.from(j as Map)))
        .toList(growable: true);
  }

  /// Send a user message; backend persists both turns and returns them plus
  /// the updated conversation title (auto-generated on the first turn).
  ///
  /// Uses a 60-second timeout because the backend chat turn does:
  /// (1) Firestore read for journey RAG, (2) OpenAI embeddings for any
  /// new/changed personal records, (3) OpenAI chat completion. On a cold
  /// start that combined work can exceed the default 15s POST timeout.
  Future<ChatTurnResult> sendMessage(int conversationId, String message) async {
    final raw = await _api.post(
      '/api/chat/conversations/$conversationId/reply',
      {'message': message},
      timeout: const Duration(seconds: 60),
    );
    final map = Map<String, dynamic>.from(raw as Map);
    return ChatTurnResult(
      conversationId: (map['conversation_id'] as num).toInt(),
      title: map['title'] as String? ?? 'New Chat',
      userMessage: ChatMessage.fromJson(Map<String, dynamic>.from(map['user_message'] as Map)),
      assistantMessage:
          ChatMessage.fromJson(Map<String, dynamic>.from(map['assistant_message'] as Map)),
    );
  }

  Future<void> deleteConversation(int conversationId) async {
    await _api.delete('/api/chat/conversations/$conversationId');
  }

  Future<ChatConversation> renameConversation(int conversationId, String title) async {
    final raw = await _api.patch(
      '/api/chat/conversations/$conversationId',
      {'title': title},
    );
    return ChatConversation.fromJson(Map<String, dynamic>.from(raw as Map));
  }
}

class ChatTurnResult {
  final int conversationId;
  final String title;
  final ChatMessage userMessage;
  final ChatMessage assistantMessage;

  const ChatTurnResult({
    required this.conversationId,
    required this.title,
    required this.userMessage,
    required this.assistantMessage,
  });
}
