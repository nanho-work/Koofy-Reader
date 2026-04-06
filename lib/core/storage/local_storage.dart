import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localStorageProvider = Provider<LocalStorage>(
  (ref) => SharedPrefsLocalStorage(),
);

abstract class LocalStorage {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix);
}

class SharedPrefsLocalStorage implements LocalStorage {
  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  @override
  Future<int?> getInt(String key) async {
    final prefs = await _prefs;
    return prefs.getInt(key);
  }

  @override
  Future<void> setInt(String key, int value) async {
    final prefs = await _prefs;
    await prefs.setInt(key, value);
  }

  @override
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix) async {
    final prefs = await _prefs;
    final result = <String, String>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      final value = prefs.getString(key);
      if (value != null) {
        result[key] = value;
      }
    }
    return result;
  }
}
