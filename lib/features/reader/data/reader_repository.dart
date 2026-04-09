import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

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
  Future<List<int>?> loadPaginationOffsets({
    required String bookId,
    required String signature,
    required int contentLength,
  });
  Future<void> savePaginationOffsets({
    required String bookId,
    required String signature,
    required int contentLength,
    required List<int> offsets,
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
  Future<List<int>?> loadPaginationOffsets({
    required String bookId,
    required String signature,
    required int contentLength,
  }) async {
    final key = _paginationKeyFor(bookId, signature);
    final raw =
        await _storage.getString(key) ??
        await _storage.getString(_legacyPaginationKeyFor(bookId, signature));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final storedLength = decoded['contentLength'];
      final offsetsRaw = decoded['offsets'];
      if (storedLength is! int || storedLength != contentLength) {
        return null;
      }
      if (offsetsRaw is! List) {
        return null;
      }
      final offsets = offsetsRaw
          .whereType<num>()
          .map((value) => value.toInt())
          .where((value) => value > 0 && value <= contentLength)
          .toList();
      if (offsets.isEmpty) {
        return null;
      }
      return offsets;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> savePaginationOffsets({
    required String bookId,
    required String signature,
    required int contentLength,
    required List<int> offsets,
  }) async {
    if (offsets.isEmpty) {
      return;
    }
    final key = _paginationKeyFor(bookId, signature);
    final payload = jsonEncode({
      'contentLength': contentLength,
      'offsets': offsets,
    });
    await _storage.setString(key, payload);
  }

  Future<void> _touchRecentBook(String bookId) async {
    final ids = await loadRecentBookIds();
    final updated = ids.where((id) => id != bookId).toList();
    updated.insert(0, bookId);
    final limited = updated.take(30).toList();
    await _storage.setString(AppConstants.recentBooksKey, jsonEncode(limited));
  }

  String _paginationKeyFor(String bookId, String signature) {
    final hashed = _stableHash(signature);
    return '${AppConstants.readerPaginationCachePrefix}${bookId}_$hashed';
  }

  String _legacyPaginationKeyFor(String bookId, String signature) {
    final hashed = signature.hashCode.toUnsigned(32);
    return '${AppConstants.readerPaginationCachePrefix}${bookId}_$hashed';
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
