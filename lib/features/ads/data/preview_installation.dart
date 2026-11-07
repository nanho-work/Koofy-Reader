import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only the hash goes to LevelPlay. The credential authenticates preview
// requests to our server and is never put in callback URLs or analytics.
class PreviewInstallation {
  static Future<String>? _loading;

  static Future<String> credential() async {
    final future = _loading ??= _load();
    try {
      return await future;
    } catch (_) {
      if (identical(_loading, future)) _loading = null;
      rethrow;
    }
  }

  static Future<String> levelPlayId() async =>
      sha256.convert(utf8.encode(await credential())).toString();

  static Future<String> _load() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'episode_preview_installation_v1';
    final saved = prefs.getString(key);
    if (saved != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(saved)) {
      return saved;
    }
    final random = Random.secure();
    final value = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    if (!await prefs.setString(key, value)) {
      throw StateError('Could not save preview installation');
    }
    return value;
  }
}
