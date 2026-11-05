import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

/// Only complete, public metadata snapshots are persisted. No signed URLs or
/// administrator drafts belong here. A failed refresh never overwrites a cache.
class CatalogCache {
  static const lifetime = Duration(minutes: 30);
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

  /// Legacy downloads did not save their source metadata. Recover by exact ID
  /// from public caches only; never search titles or contact every series.
  Future<Map<String, dynamic>?> findBook(String bookId, String endpoint) async {
    final identity = RegExp(
      r'^catalog_([a-f0-9]{32})_[1-9][0-9]*$',
    ).firstMatch(bookId)?.group(1);
    if (identity == null) return null;
    Map<String, dynamic>? find(Map<String, dynamic> snapshot) {
      if (!(snapshot['key'] as String? ?? '').startsWith('$endpoint|')) {
        return null;
      }
      for (final raw in (snapshot['items'] as List? ?? const [])) {
        if (raw is Map && raw['id'] == identity) {
          return Map<String, dynamic>.from(raw);
        }
      }
      return null;
    }

    for (final snapshot in _memory.values) {
      final item = find(snapshot);
      if (item != null) return item;
    }
    if (directory == null) return null;
    final folder = Directory('${(await directory!()).path}/catalog_lists');
    if (!await folder.exists()) return null;
    await for (final entry in folder.list()) {
      if (entry is! File || !entry.path.endsWith('.json')) continue;
      try {
        if (await entry.length() > 8 * 1024 * 1024) continue;
        final snapshot = jsonDecode(await entry.readAsString());
        if (snapshot is Map<String, dynamic> && snapshot['version'] == 1) {
          final item = find(snapshot);
          if (item != null) return item;
        }
      } catch (_) {
        /* A corrupt optional cache never prevents local reading. */
      }
    }
    return null;
  }

  bool fresh(Map<String, dynamic> value) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = value['nextChange'] as int?;
    return now >= (value['at'] as int) &&
        now - (value['at'] as int) < lifetime.inMilliseconds &&
        (next == null || next > now);
  }

  Duration refreshDelay(Map<String, dynamic>? value) {
    if (value == null) return lifetime;
    final now = DateTime.now().millisecondsSinceEpoch;
    var due = (value['at'] as int) + lifetime.inMilliseconds;
    final next = value['nextChange'] as int?;
    if (next != null && next < due) due = next;
    // A failed refresh retains stale data. Avoid a tight retry loop in that case.
    return due > now ? Duration(milliseconds: due - now) : lifetime;
  }
}
