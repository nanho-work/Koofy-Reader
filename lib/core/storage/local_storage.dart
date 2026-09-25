import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localStorageProvider = Provider<LocalStorage>(
  (ref) => SharedPrefsLocalStorage(),
);

abstract class LocalStorage {
  Future<void> remove(String key);
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix);
}

class SharedPrefsLocalStorage implements LocalStorage {
  final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Future<SharedPreferences> get _prefs async => _prefsFuture;

  @override
  Future<void> remove(String key) async {
    if (!await (await _prefs).remove(key)) {
      throw StateError('기록을 복구하지 못했습니다. 저장 공간을 확인해 주세요.');
    }
  }

  @override
  Future<String?> getString(String key) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    final prefs = await _prefs;
    if (!await prefs.setString(key, value)) throw StateError('기록을 저장하지 못했습니다.');
  }

  @override
  Future<int?> getInt(String key) async {
    final prefs = await _prefs;
    return prefs.getInt(key);
  }

  @override
  Future<void> setInt(String key, int value) async {
    final prefs = await _prefs;
    if (!await prefs.setInt(key, value)) throw StateError('설정을 저장하지 못했습니다.');
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
