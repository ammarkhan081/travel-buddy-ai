import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Base URL for the FastAPI backend.
  ///
  /// Priority:
  /// 1) `--dart-define=API_BASE_URL=...`
  /// 2) Platform default for local development
  static String get baseUrl {
    final defined = _definedBaseUrl.trim();
    if (defined.isNotEmpty) return _normalizeBaseUrl(defined);

    if (kIsWeb) return 'http://127.0.0.1:8000';
    return _defaultMobileOrDesktopBaseUrl;
  }

  static String get _defaultMobileOrDesktopBaseUrl {
    // Android emulators access host machine localhost via 10.0.2.2.
    // Physical devices should use --dart-define=API_BASE_URL=http://<LAN_IP>:8000.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      default:
        return 'http://127.0.0.1:8000';
    }
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static const String authTokenKey = 'auth_token';
}
