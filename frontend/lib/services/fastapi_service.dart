import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';

import 'api_exceptions.dart';

class FastApiService {
  static final FastApiService _instance = FastApiService._internal();
  factory FastApiService() => _instance;
  FastApiService._internal();

  final Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 15);
  static const int _maxRetries = 2; // Total 3 attempts

  Uri _buildUri(String endpoint, {Map<String, String>? queryParams}) {
    final safeBase = AppConfig.baseUrl.endsWith('/')
        ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
        : AppConfig.baseUrl;
    return Uri.parse('$safeBase$endpoint').replace(
      queryParameters: queryParams,
    );
  }

  NetworkException _networkException(
    Object error, {
    required String endpoint,
  }) {
    final configuredBaseUrl = AppConfig.baseUrl;
    final hint =
        'Check backend URL and server status. If using physical Android, run backend on 0.0.0.0 and use your PC LAN IP via --dart-define=API_BASE_URL=http://<PC_LAN_IP>:8000';

    if (error is SocketException) {
      return NetworkException(
        'Cannot reach backend at $configuredBaseUrl$endpoint. ${error.message}. $hint',
      );
    }

    if (error is TimeoutException) {
      return NetworkException(
        'Request timed out for $configuredBaseUrl$endpoint. $hint',
      );
    }

    return NetworkException(
      'Connection failed for $configuredBaseUrl$endpoint: $error. $hint',
    );
  }

  /// Get current Firebase ID Token for backend authentication.
  /// M-7: Uses forceRefresh=false by default to avoid extra Firebase round-trip.
  /// Pass forceRefresh=true to force a new token (used on 401 retry).
  Future<String?> _getToken({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return await user.getIdToken(forceRefresh);
    }
    return null;
  }

  /// Appends Authorization header with current user's token
  Future<Map<String, String>> _getRequestHeaders({bool forceRefresh = false}) async {
    final headers = Map<String, String>.from(_headers);
    final token = await _getToken(forceRefresh: forceRefresh);
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Generic GET request with M-7 401-token-refresh retry
  Future<dynamic> get(String endpoint, {Map<String, String>? queryParams}) async {
    final uri = _buildUri(endpoint, queryParams: queryParams);
    var headers = await _getRequestHeaders();

    debugPrint('GET REQUEST: $uri');
    bool refreshed = false;
    int attempts = 0;
    while (attempts <= _maxRetries) {
      try {
        final response = await http.get(uri, headers: headers).timeout(_timeout);
        try {
          return _handleResponse(response);
        } on AuthException {
          if (!refreshed) {
            refreshed = true;
            headers = await _getRequestHeaders(forceRefresh: true);
            continue; // retry immediately with fresh token
          }
          rethrow;
        }
      } catch (e) {
        if (e is AuthException) rethrow;
        attempts++;
        if (attempts > _maxRetries || e is ApiResponseException) {
          if (e is ApiResponseException) rethrow;
          throw _networkException(e, endpoint: endpoint);
        }
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  /// Generic PUT request
  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    final uri = _buildUri(endpoint);
    var headers = await _getRequestHeaders();

    debugPrint('POST REQUEST: $uri | BODY: $body');
    bool refreshed = false;
    int attempts = 0;
    while (attempts <= _maxRetries) {
      try {
        final response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body),
        ).timeout(_timeout);
        if ((response.statusCode == 401 || response.statusCode == 403) && !refreshed) {
          refreshed = true;
          headers = await _getRequestHeaders(forceRefresh: true);
          continue;
        }
        return _handleResponse(response);
      } catch (e) {
        if (e is AuthException) rethrow;
        attempts++;
        // Don't retry POSTs generally unless they are specific network errors
        if (attempts > _maxRetries || e is ApiResponseException || e is! SocketException) {
          if (e is ApiResponseException) rethrow;
          throw _networkException(e, endpoint: endpoint);
        }
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  /// Generic PUT request
  Future<dynamic> put(String endpoint, Map<String, dynamic> body) async {
    final uri = _buildUri(endpoint);
    var headers = await _getRequestHeaders();

    debugPrint('PUT REQUEST: $uri | BODY: $body');
    bool refreshed = false;
    int attempts = 0;
    while (attempts <= _maxRetries) {
      try {
        final response = await http.put(
          uri,
          headers: headers,
          body: jsonEncode(body),
        ).timeout(_timeout);
        if ((response.statusCode == 401 || response.statusCode == 403) && !refreshed) {
          refreshed = true;
          headers = await _getRequestHeaders(forceRefresh: true);
          continue;
        }
        return _handleResponse(response);
      } catch (e) {
        if (e is AuthException) rethrow;
        attempts++;
        if (attempts > _maxRetries || e is ApiResponseException || e is! SocketException) {
          if (e is ApiResponseException) rethrow;
          throw _networkException(e, endpoint: endpoint);
        }
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  /// Generic DELETE request
  Future<dynamic> delete(String endpoint) async {
    final uri = _buildUri(endpoint);
    var headers = await _getRequestHeaders();

    debugPrint('DELETE REQUEST: $uri');
    bool refreshed = false;
    int attempts = 0;
    while (attempts <= _maxRetries) {
      try {
        final response = await http.delete(uri, headers: headers).timeout(_timeout);
        if ((response.statusCode == 401 || response.statusCode == 403) && !refreshed) {
          refreshed = true;
          headers = await _getRequestHeaders(forceRefresh: true);
          continue;
        }
        return _handleResponse(response);
      } catch (e) {
        if (e is AuthException) rethrow;
        attempts++;
        if (attempts > _maxRetries || e is ApiResponseException || e is! SocketException) {
          if (e is ApiResponseException) rethrow;
          throw _networkException(e, endpoint: endpoint);
        }
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  /// Multi-part POST for audio files
  Future<dynamic> postVoice(String endpoint, File file, {Map<String, String>? queryParams}) async {
    final uri = _buildUri(endpoint, queryParams: queryParams);
    
    debugPrint('VOICE POST REQUEST: $uri | FILE: ${file.path}');
    bool refreshed = false;
    int attempts = 0;
    while (attempts <= _maxRetries) {
      try {
        // MultipartRequest doesn't have a direct .timeout, so we use a different approach
        // or just accept that streaming might take longer. We'll use a Future.timeout on the send.
        final request = http.MultipartRequest('POST', uri);
        final token = await _getToken(forceRefresh: refreshed);
        if (token != null) request.headers['Authorization'] = 'Bearer $token';
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
        final response = await http.Response.fromStream(streamedResponse);
        if ((response.statusCode == 401 || response.statusCode == 403) && !refreshed) {
          refreshed = true;
          continue;
        }
        return _handleResponse(response);
      } catch (e) {
        if (e is AuthException) rethrow;
        attempts++;
        if (attempts > _maxRetries || e is ApiResponseException) {
          if (e is ApiResponseException) rethrow;
          throw _networkException(e, endpoint: endpoint);
        }
        await Future.delayed(Duration(seconds: attempts));
      }
    }
  }

  dynamic _handleResponse(http.Response response) {
    debugPrint('API RESPONSE: [${response.statusCode}] ${response.body}');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    } else {
      String message = 'Unknown API Error';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded.containsKey('detail')) {
          message = decoded['detail'];
        }
      } catch (_) {}

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthException(message, statusCode: response.statusCode);
      } else if (response.statusCode == 422) {
        throw ValidationException(message, statusCode: response.statusCode);
      } else if (response.statusCode >= 500) {
        throw ServerException('Server-side error occurred. Please try again later.', statusCode: response.statusCode);
      } else {
        throw ApiResponseException(message, statusCode: response.statusCode);
      }
    }
  }
}
