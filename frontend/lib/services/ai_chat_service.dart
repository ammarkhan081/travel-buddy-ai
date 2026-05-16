import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

enum AiProvider {
  openAiCompatible,
  gemini,
}

class AiChatConfig {
  final AiProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;

  const AiChatConfig({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  bool get isValid {
    if (provider == AiProvider.gemini) {
      return apiKey.trim().isNotEmpty;
    }
    // OpenAI-compatible mode is backend-routed; backend owns the API key.
    return baseUrl.trim().isNotEmpty;
  }
}

class AiChatService {
  /// Calls an OpenAI-compatible Chat Completions endpoint:
  /// POST {baseUrl}/v1/chat/completions
  ///
  /// Works with providers that support the OpenAI schema (including many self-hosted gateways).
  static Future<String> generateReply({
    required AiChatConfig config,
    required List<Map<String, String>> messages,
    Duration timeout = const Duration(seconds: 20),
    String userId = 'default',
  }) async {
    if (!config.isValid) {
      throw const AiChatException(
        'AI is not configured. Open AI Settings and check provider/base URL.',
      );
    }

    if (config.provider == AiProvider.gemini) {
      return _generateGeminiReply(
        config: config,
        messages: messages,
        timeout: timeout,
      );
    }

    // For OpenAI-compatible providers, route through our backend to get Trip Memory (RAG)
    // assuming the backend is running on the same host or a configured base URL.
    // We'll use the provided baseUrl from config, but point it to our backend's chat endpoint.
    final base = config.baseUrl.trim();
    final normalizedBase =
        base.startsWith('http://') || base.startsWith('https://')
            ? base
            : 'https://$base';
    
    // Check if the base URL points to our backend (usually localhost:8000 or similar in dev)
    // or if we should just always use our backend for "Travel Buddy" logic.
    // For FYP, we'll assume the backend handles the RAG logic.
    final uri = Uri.parse(
      '${normalizedBase.replaceAll(RegExp(r'/+$'), '')}/api/chat/reply',
    );

    final body = <String, dynamic>{
      'messages': messages
          .map((m) => {
                'role': m['role'],
                'content': m['content'],
              })
          .toList(),
      'user_id': userId,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final token = await currentUser.getIdToken();
      if (token != null && token.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
      if ((res.statusCode == 401 || res.statusCode == 403) && currentUser != null) {
        final refreshed = await currentUser.getIdToken(true);
        if (refreshed != null && refreshed.trim().isNotEmpty) {
          headers['Authorization'] = 'Bearer $refreshed';
          res = await http
              .post(
                uri,
                headers: headers,
                body: jsonEncode(body),
              )
              .timeout(timeout);
        }
      }
    } catch (e) {
      throw AiChatException(
        'Network/timeout error while contacting Travel Buddy Backend. ($e)',
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiChatException('Travel Buddy AI request failed (${res.statusCode}): ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final reply = decoded['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const AiChatException('Travel Buddy AI returned an empty message.');
    }

    return reply.trim();
  }

  static Future<String> _generateGeminiReply({
    required AiChatConfig config,
    required List<Map<String, String>> messages,
    required Duration timeout,
  }) async {
    // Gemini (Google AI) Generative Language API:
    // POST https://generativelanguage.googleapis.com/v1/models/{model}:generateContent?key=API_KEY
    //
    // We map chat messages into one prompt string to keep the implementation simple.
    var model = config.model.trim().isEmpty ? 'gemini-1.5-flash' : config.model.trim();
    // Accept common inputs like "models/gemini-1.5-flash" without breaking the URL.
    if (model.startsWith('models/')) {
      model = model.substring('models/'.length);
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models/$model:generateContent?key=${Uri.encodeQueryComponent(config.apiKey)}',
    );

    final prompt = messages.map((m) {
      final role = (m['role'] ?? 'user').toUpperCase();
      final content = m['content'] ?? '';
      return '$role: $content';
    }).join('\n');

    final body = <String, dynamic>{
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.7,
      },
    };

    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (e) {
      throw AiChatException(
        'Network/timeout error while contacting Gemini. Check internet and try again. ($e)',
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      // Try to extract Gemini error message
      try {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            throw AiChatException(
              'Gemini request failed (${res.statusCode}): ${message.trim()}',
            );
          }
        }
      } catch (_) {
        // ignore parsing errors
      }
      throw AiChatException('Gemini request failed (${res.statusCode}): ${res.body}');
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const AiChatException('Gemini returned no candidates.');
    }

    final content = (candidates.first as Map<String, dynamic>)['content'];
    if (content is! Map<String, dynamic>) {
      throw const AiChatException('Gemini returned invalid content.');
    }

    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const AiChatException('Gemini returned empty parts.');
    }

    final text = (parts.first as Map<String, dynamic>)['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const AiChatException('Gemini returned an empty message.');
    }

    return text.trim();
  }
}

class AiChatException implements Exception {
  final String message;
  const AiChatException(this.message);
  @override
  String toString() => message;
}
