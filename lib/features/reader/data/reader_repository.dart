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

abstract class ReaderRepository {
  Future<ReadingProgress?> loadProgress(String bookId);
  Future<void> saveProgress(ReadingProgress progress);
  Future<Map<String, ReadingProgress>> loadAllProgress();
}

class LocalReaderRepository implements ReaderRepository {
  LocalReaderRepository(this._storage);

  final LocalStorage _storage;

  String _keyFor(String bookId) =>
      '${AppConstants.readingProgressPrefix}$bookId';

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
}
