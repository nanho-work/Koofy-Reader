import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saved reading background. Legacy key is retained to preserve existing choices.
/// The app shell is always light and does not consume this mode.
class AppAppearance extends ChangeNotifier {
  static final instance = AppAppearance();
  static const preferenceKey = 'app_theme_v1';
  String _selection = 'system';
  String get selection => _selection;
  ThemeMode get mode => switch (_selection) {
    'dark' => ThemeMode.dark,
    'light' || 'sepia' => ThemeMode.light,
    _ => ThemeMode.system,
  };
  Future<void> initialize({SharedPreferences? preferences}) async {
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final saved = prefs.getString(preferenceKey);
    _selection = const ['system', 'light', 'sepia', 'dark'].contains(saved)
        ? saved!
        : 'system';
    notifyListeners();
  }

  Future<void> select(ThemeMode mode) => selectBackground(mode.name);
  Future<void> selectBackground(String selection) async {
    if (!const ['system', 'light', 'sepia', 'dark'].contains(selection)) {
      throw ArgumentError.value(selection);
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(preferenceKey, selection)) {
      throw StateError('Could not save theme');
    }
    _selection = selection;
    notifyListeners();
  }
}
