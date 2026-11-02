import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Only complete, public metadata snapshots are persisted. No signed URLs or
/// administrator drafts belong here. A failed refresh never overwrites a cache.
class CatalogCache {
  CatalogCache(this.directory);
  CatalogCache.memory() : directory = null;
  final Future<Directory> Function()? directory;
  final _memory = <String, Map<String, dynamic>>{};
  Future<File> _file(String key) async => File(
    '${(await directory!()).path}/catalog_lists/${sha256.convert(utf8.encode(key))}.json',
  );
  Future<Map<String, dynamic>?> read(String key) async {
    if (_memory.containsKey(key)) return _memory[key];
    if (directory == null) return null;
    try {
      final file = await _file(key);
      if (!await file.exists() || await file.length() > 8 * 1024 * 1024) {
        return null;
      }
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (value['version'] != 1 ||
          value['key'] != key ||
          value['items'] is! List ||
          value['at'] is! int) {
        return null;
      }
      return _memory[key] = value;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(
    String key,
    List<Map<String, dynamic>> items, {
    DateTime? nextChange,
  }) async {
    final value = {
      'version': 1,
      'key': key,
      'items': items,
      'at': DateTime.now().millisecondsSinceEpoch,
      'nextChange': nextChange?.millisecondsSinceEpoch,
    };
    _memory[key] = value;
    if (_memory.length > 24) _memory.remove(_memory.keys.first);
    if (directory == null) return;
    final file = await _file(key);
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    await temp.writeAsString(jsonEncode(value), flush: true);
    await temp.rename(file.path);
  }

  bool fresh(Map<String, dynamic> value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = value['nextChange'] as int?;
    return now >= (value['at'] as int) &&
        now - (value['at'] as int) < 60 * 1000 &&
        (next == null || next > now);
  }
}
