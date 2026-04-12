import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:path_provider/path_provider.dart';

final readerRepositoryProvider = Provider<ReaderRepository>(
  (ref) => LocalReaderRepository(ref.watch(localStorageProvider)),
);

final allReadingProgressProvider = FutureProvider<Map<String, ReadingProgress>>(
  (ref) => ref.watch(readerRepositoryProvider).loadAllProgress(),
);

final recentBookIdsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(readerRepositoryProvider).loadRecentBookIds(),
);

abstract class ReaderRepository {
  Future<ReadingProgress?> loadProgress(String bookId);
  Future<void> saveProgress(ReadingProgress progress);
  Future<Map<String, ReadingProgress>> loadAllProgress();
  Future<Set<int>> loadBookmarks(String bookId);
  Future<void> saveBookmarks(String bookId, Set<int> pages);
  Future<List<String>> loadRecentBookIds();
  Future<List<String>> loadSearchHistory();
  Future<void> saveSearchHistory(List<String> history);
  Future<ReaderStructureIndex?> loadStructureIndex({
    required String bookId,
    required int contentLength,
    required String contentHash,
  });
  Future<void> saveStructureIndex({
    required String bookId,
    required ReaderStructureIndex index,
  });
}

class LocalReaderRepository implements ReaderRepository {
  LocalReaderRepository(this._storage);

  final LocalStorage _storage;

  String _keyFor(String bookId) =>
      '${AppConstants.readingProgressPrefix}$bookId';

  String _bookmarkKeyFor(String bookId) =>
      '${AppConstants.readingBookmarkPrefix}$bookId';

  @override
  Future<ReadingProgress?> loadProgress(String bookId) async {
    final raw = await _storage.getString(_keyFor(bookId));
    if (raw == null) {
      return null;
    }
    return ReadingProgress.fromRaw(raw);
  }

  @override
  Future<void> saveProgress(ReadingProgress progress) async {
    await _storage.setString(_keyFor(progress.bookId), progress.toRaw());
    await _touchRecentBook(progress.bookId);
  }

  @override
  Future<Map<String, ReadingProgress>> loadAllProgress() async {
    final entries = await _storage.getStringEntriesByPrefix(
      AppConstants.readingProgressPrefix,
    );
    final progressMap = <String, ReadingProgress>{};
    for (final entry in entries.entries) {
      final parsed = ReadingProgress.fromRaw(entry.value);
      if (parsed != null) {
        progressMap[parsed.bookId] = parsed;
      }
    }
    return progressMap;
  }

  @override
  Future<Set<int>> loadBookmarks(String bookId) async {
    final raw = await _storage.getString(_bookmarkKeyFor(bookId));
    if (raw == null) {
      return <int>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <int>{};
      }
      return decoded
          .whereType<num>()
          .map((value) => value.toInt())
          .where((value) => value >= 0)
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  @override
  Future<void> saveBookmarks(String bookId, Set<int> pages) async {
    final sorted = pages.toList()..sort();
    await _storage.setString(_bookmarkKeyFor(bookId), jsonEncode(sorted));
  }

  @override
  Future<List<String>> loadRecentBookIds() async {
    final raw = await _storage.getString(AppConstants.recentBooksKey);
    if (raw == null) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<String>> loadSearchHistory() async {
    final raw = await _storage.getString(AppConstants.readerSearchHistoryKey);
    if (raw == null) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final history = decoded
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      return history.take(12).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveSearchHistory(List<String> history) async {
    final seen = <String>{};
    final normalized = <String>[];
    for (final item in history) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(trimmed.toLowerCase())) continue;
      normalized.add(trimmed);
      if (normalized.length >= 12) break;
    }
    await _storage.setString(
      AppConstants.readerSearchHistoryKey,
      jsonEncode(normalized),
    );
  }

  @override
  Future<ReaderStructureIndex?> loadStructureIndex({
    required String bookId,
    required int contentLength,
    required String contentHash,
  }) async {
    final fromFile = await _loadStructureIndexFromFile(
      bookId: bookId,
      contentLength: contentLength,
      contentHash: contentHash,
    );
    if (fromFile != null) {
      return fromFile;
    }

    // Legacy fallback: previously persisted in SharedPreferences.
    final key = _structureIndexKeyFor(bookId);
    final raw = await _storage.getString(key);
    final parsed = _parseStructureIndexIfValid(
      raw: raw,
      contentLength: contentLength,
      contentHash: contentHash,
    );
    if (parsed == null) {
      return null;
    }
    await saveStructureIndex(bookId: bookId, index: parsed);
    return parsed;
  }

  @override
  Future<void> saveStructureIndex({
    required String bookId,
    required ReaderStructureIndex index,
  }) async {
    final payload = index.toRaw();
    // Guard against pathological payload sizes.
    if (payload.length > 8 * 1024 * 1024) {
      return;
    }
    try {
      final file = await _structureIndexFileFor(bookId);
      await file.parent.create(recursive: true);
      await file.writeAsString(payload, flush: true);
    } catch (_) {
      // Ignore write failures and continue without cache.
    }
  }

  Future<void> _touchRecentBook(String bookId) async {
    final ids = await loadRecentBookIds();
    final updated = ids.where((id) => id != bookId).toList();
    updated.insert(0, bookId);
    final limited = updated.take(30).toList();
    await _storage.setString(AppConstants.recentBooksKey, jsonEncode(limited));
  }

  String _structureIndexKeyFor(String bookId) {
    return '${AppConstants.readerStructureIndexPrefix}$bookId';
  }

  Future<ReaderStructureIndex?> _loadStructureIndexFromFile({
    required String bookId,
    required int contentLength,
    required String contentHash,
  }) async {
    try {
      final file = await _structureIndexFileFor(bookId);
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      final parsed = _parseStructureIndexIfValid(
        raw: raw,
        contentLength: contentLength,
        contentHash: contentHash,
      );
      if (parsed == null) {
        await file.delete();
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  ReaderStructureIndex? _parseStructureIndexIfValid({
    required String? raw,
    required int contentLength,
    required String contentHash,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final parsed = ReaderStructureIndex.fromRaw(raw);
    if (parsed == null) {
      return null;
    }
    if (parsed.schemaVersion != ReaderStructureIndex.currentSchemaVersion) {
      return null;
    }
    if (parsed.contentLength != contentLength ||
        parsed.contentHash != contentHash) {
      return null;
    }
    return parsed;
  }

  Future<File> _structureIndexFileFor(String bookId) async {
    final baseDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${baseDir.path}/reader_index_cache');
    final safeId = _stableHash(bookId);
    return File('${cacheDir.path}/$safeId.json');
  }

  String _stableHash(String value) {
    // FNV-1a 32-bit: deterministic across app restarts.
    const int fnvOffsetBasis = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffsetBasis;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
