import 'dart:convert';

import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

class StorageMigrationRunner {
  StorageMigrationRunner({LocalStorage? storage})
    : _storage = storage ?? SharedPrefsLocalStorage();

  final LocalStorage _storage;
  static const int _latestVersion = 2;

  Future<void> run() async {
    final current =
        await _storage.getInt(AppConstants.storageSchemaVersionKey) ?? 0;
    if (current >= _latestVersion) {
      return;
    }

    if (current < 1) {
      await _migrateReadingProgressRecords();
    }
    if (current < 2) {
      await _migrateSearchHistory();
      await _migrateRecentBookIds();
    }

    await _storage.setInt(AppConstants.storageSchemaVersionKey, _latestVersion);
  }

  Future<void> _migrateReadingProgressRecords() async {
    final entries = await _storage.getStringEntriesByPrefix(
      AppConstants.readingProgressPrefix,
    );
    for (final entry in entries.entries) {
      final raw = entry.value;
      final parsed = ReadingProgress.fromRaw(raw);
      if (parsed != null) {
        await _storage.setString(entry.key, parsed.toRaw());
        continue;
      }

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final bookId = decoded['bookId'];
        final ratio = decoded['positionRatio'];
        final updatedAt = decoded['updatedAt'];
        if (bookId is! String || ratio is! num || updatedAt is! int) {
          continue;
        }
        final normalized = ReadingProgress(
          bookId: bookId,
          positionRatio: ratio.toDouble().clamp(0.0, 1.0),
          pageIndex: 0,
          totalPages: 0,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
        );
        await _storage.setString(entry.key, normalized.toRaw());
      } catch (_) {
        // Ignore malformed legacy entries.
      }
    }
  }

  Future<void> _migrateSearchHistory() async {
    final raw = await _storage.getString(AppConstants.readerSearchHistoryKey);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    final normalized = _normalizeStringList(raw, maxItems: 12);
    await _storage.setString(
      AppConstants.readerSearchHistoryKey,
      jsonEncode(normalized),
    );
  }

  Future<void> _migrateRecentBookIds() async {
    final raw = await _storage.getString(AppConstants.recentBooksKey);
    if (raw == null || raw.trim().isEmpty) {
      return;
    }

    final normalized = _normalizeStringList(raw, maxItems: 30);
    await _storage.setString(
      AppConstants.recentBooksKey,
      jsonEncode(normalized),
    );
  }

  List<String> _normalizeStringList(String raw, {required int maxItems}) {
    final seen = <String>{};
    final normalized = <String>[];

    void push(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (seen.add(trimmed.toLowerCase())) {
        normalized.add(trimmed);
      }
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded.whereType<String>()) {
          push(item);
          if (normalized.length >= maxItems) {
            break;
          }
        }
        return normalized;
      }
      if (decoded is String) {
        for (final part in decoded.split(RegExp(r'[,;\n]'))) {
          push(part);
          if (normalized.length >= maxItems) {
            break;
          }
        }
        return normalized;
      }
    } catch (_) {
      // Legacy fallback: plain string joined by comma/newline.
    }

    for (final part in raw.split(RegExp(r'[,;\n]'))) {
      push(part);
      if (normalized.length >= maxItems) {
        break;
      }
    }
    return normalized;
  }
}
