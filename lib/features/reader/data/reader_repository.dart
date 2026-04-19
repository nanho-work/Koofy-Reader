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
}

class LocalReaderRepository implements ReaderRepository {
  LocalReaderRepository(this._storage);

  final LocalStorage _storage;
  Map<String, ReadingProgress>? _allProgressCache;
  bool _allProgressDirty = true;
  List<String>? _recentBookIdsCache;

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
    _allProgressCache ??= <String, ReadingProgress>{};
    _allProgressCache![progress.bookId] = progress;
    _allProgressDirty = false;
    await _touchRecentBook(progress.bookId);
  }

  @override
  Future<Map<String, ReadingProgress>> loadAllProgress() async {
    if (!_allProgressDirty && _allProgressCache != null) {
      return Map<String, ReadingProgress>.from(_allProgressCache!);
    }
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
    _allProgressCache = progressMap;
    _allProgressDirty = false;
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
    if (_recentBookIdsCache != null) {
      return List<String>.from(_recentBookIdsCache!);
    }
    final raw = await _storage.getString(AppConstants.recentBooksKey);
    if (raw == null) {
      _recentBookIdsCache = const <String>[];
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _recentBookIdsCache = const <String>[];
        return const [];
      }
      final ids = decoded.whereType<String>().toList();
      _recentBookIdsCache = ids;
      return List<String>.from(ids);
    } catch (_) {
      _recentBookIdsCache = const <String>[];
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

  Future<void> _touchRecentBook(String bookId) async {
    final ids = await loadRecentBookIds();
    if (ids.isNotEmpty && ids.first == bookId) {
      return;
    }
    final updated = ids.where((id) => id != bookId).toList();
    updated.insert(0, bookId);
    final limited = updated.take(30).toList();
    _recentBookIdsCache = limited;
    await _storage.setString(AppConstants.recentBooksKey, jsonEncode(limited));
  }
}
