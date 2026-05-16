import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'darkmode.dart';
import 'lightmode.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  ThemeData get lightTheme => buildLightTheme();
  ThemeData get darkTheme => buildDarkTheme();

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('app.themeMode') ?? 'system';
    _themeMode = _stringToThemeMode(value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app.themeMode', _themeModeToString(mode));
  }

  Future<void> toggleLightDark() {
    if (_themeMode == ThemeMode.dark) {
      return setThemeMode(ThemeMode.light);
    }
    return setThemeMode(ThemeMode.dark);
  }

  ThemeMode _stringToThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

