import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class ThemeProvider extends ChangeNotifier {
  static const String _storageKey = 'gymos_admin_theme_mode';
  ThemeMode _mode = ThemeMode.light;

  ThemeProvider() {
    _loadTheme();
  }

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void _loadTheme() {
    if (kIsWeb) {
      try {
        final saved = html.window.localStorage[_storageKey];
        if (saved == 'dark') {
          _mode = ThemeMode.dark;
        } else if (saved == 'light') {
          _mode = ThemeMode.light;
        }
      } catch (e) {
        debugPrint('Error reading theme from localStorage: $e');
      }
    }
  }

  void _saveTheme() {
    if (kIsWeb) {
      try {
        html.window.localStorage[_storageKey] =
            _mode == ThemeMode.dark ? 'dark' : 'light';
      } catch (e) {
        debugPrint('Error saving theme to localStorage: $e');
      }
    }
  }

  void toggle() {
    _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    _saveTheme();
    notifyListeners();
  }

  void setTheme(ThemeMode mode) {
    _mode = mode;
    _saveTheme();
    notifyListeners();
  }
}

