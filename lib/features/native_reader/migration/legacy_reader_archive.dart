import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/core/utils/hash_utils.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reading_progress.dart';

final legacyReaderArchiveProvider = Provider(
  (ref) => LegacyReaderArchive(ref.watch(localStorageProvider)),
);
final legacyReadingProgressProvider =
    FutureProvider<Map<String, ReadingProgress>>(
      (ref) => ref.watch(legacyReaderArchiveProvider).loadProgress(),
    );

/// Compatibility data only. There is no legacy renderer or progress writer.
/// Keep an immutable raw snapshot BEFORE interpreting or normalizing any record.
class LegacyReaderArchive {
  LegacyReaderArchive(this.storage);
  final LocalStorage storage;
  static const backupKey = 'readium_cutover_legacy_backup_v1';

  Future<Map<String, String>> backup() async {
    final existing = await storage.getString(backupKey);
    if (existing != null) {
      return (jsonDecode(existing) as Map).cast<String, String>();
    }
    final entries = <String, String>{};
    for (final prefix in [
      AppConstants.readingProgressPrefix,
      AppConstants.readingBookmarkPrefix,
    ]) {
      entries.addAll(await storage.getStringEntriesByPrefix(prefix));
    }
    for (final key in [
      AppConstants.readerSettingsKey,
      AppConstants.readerSearchHistoryKey,
      AppConstants.recentBooksKey,
    ]) {
      final value = await storage.getString(key);
      if (value != null) entries[key] = value;
    }
    await storage.setString(backupKey, jsonEncode(entries));
    return entries;
  }

  Future<Map<String, ReadingProgress>> loadProgress() async {
    final data = await backup();
    return {
      for (final entry in data.entries)
        if (entry.key.startsWith(AppConstants.readingProgressPrefix))
          if (ReadingProgress.fromRaw(entry.value) case final progress?)
            entry.key.substring(AppConstants.readingProgressPrefix.length):
                progress,
    };
  }

  Future<LegacyBookRecord?> loadBook(
    String bookId, {
    Directory? support,
  }) async {
    final data = await backup();
    final rawProgress = data['${AppConstants.readingProgressPrefix}$bookId'];
    final rawBookmarks = data['${AppConstants.readingBookmarkPrefix}$bookId'];
    if (rawProgress == null && rawBookmarks == null) return null;
    final offsets = <int>[];
    try {
      final decoded = jsonDecode(rawBookmarks ?? '[]');
      if (decoded is List) {
        offsets.addAll(
          decoded.whereType<int>().where((offset) => offset >= 0).toSet(),
        );
        offsets.sort();
      }
    } on FormatException {
      /* Raw damaged records remain in the archive. */
    }
    String? cachedText;
    if (support != null) {
      final cache = File(
        '${support.path}/reader_content_cache/${HashUtils.fnv1a32(bookId)}.json',
      );
      final backup = File(
        '${support.path}/native_reader_v1/legacy_cache/${sha256.convert(utf8.encode(bookId))}.json',
      );
      if (!await backup.exists() && await cache.exists()) {
        await backup.parent.create(recursive: true);
        final staging = File('${backup.path}.tmp');
        await staging.writeAsBytes(await cache.readAsBytes(), flush: true);
        await staging.rename(backup.path);
      }
      if (await backup.exists()) {
        try {
          final decoded = jsonDecode(await backup.readAsString());
          if (decoded is Map && decoded['normalizedContent'] is String) {
            cachedText = decoded['normalizedContent'] as String;
          }
        } on FormatException {
          /* Preserve the damaged cache too. */
        }
      }
    }
    return LegacyBookRecord(
      progress: rawProgress == null
          ? null
          : ReadingProgress.fromRaw(rawProgress),
      hasProgress: rawProgress != null,
      bookmarks: offsets,
      cachedText: cachedText,
      rawProgress: rawProgress,
      rawBookmarks: rawBookmarks,
    );
  }
}

class LegacyBookRecord {
  const LegacyBookRecord({
    required this.progress,
    required this.hasProgress,
    required this.bookmarks,
    required this.cachedText,
    required this.rawProgress,
    required this.rawBookmarks,
  });
  final ReadingProgress? progress;
  final bool hasProgress;
  final List<int> bookmarks;
  final String? cachedText;
  final String? rawProgress;
  final String? rawBookmarks;

  /// The old canonical content offset has precedence over the spread's visual
  /// start. Using doublePageStartOffset here would recreate the reported drift.
  int? get offset {
    if (rawProgress == null) return null;
    try {
      final raw = jsonDecode(rawProgress!);
      if (raw is! Map) return null;
      final locator = raw['locator'];
      final value = locator is Map ? locator['globalOffset'] : null;
      final offset = value ?? raw['contentOffset'];
      return offset is int && offset >= 0 ? offset : null;
    } on FormatException {
      return null;
    }
  }

  String excerpt(int? offset) {
    final text = cachedText;
    if (text == null || offset == null || offset >= text.length) {
      return '원문 위치를 직접 확인해 주세요.';
    }
    return text.substring(offset, (offset + 120).clamp(0, text.length)).trim();
  }
}
