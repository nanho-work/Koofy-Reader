import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/library/domain/library_reading_state.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reading_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReadingProgress progress(String id, DateTime date) => ReadingProgress(
  bookId: id,
  positionRatio: .25,
  contentOffset: 500,
  updatedAt: date,
);

void main() {
  final oldDate = DateTime(2026, 9, 18);
  final newDate = DateTime(2026, 9, 19);
  LibraryReadingState merged({
    DateTime? nativeDate,
    String? locator,
  }) => mergeLibraryReadingStates(
    legacy: {'book': progress('book', oldDate)},
    native: [
      NativeLibraryPosition(
        publicationId: 'book',
        lastOpenedAt: nativeDate,
        locatorJson:
            locator ??
            '{"href":"ch2.xhtml","title":"두 번째 장","locations":{"progression":0.8,"totalProgression":0.42}}',
      ),
    ],
    completion: {'book': true},
  )['book']!;

  test('native state uses whole-book ratio and completion', () {
    final value = merged(nativeDate: newDate);
    expect(value.needsMigration, isFalse);
    expect(value.progression, .42);
    expect(value.chapterTitle, '두 번째 장');
    expect(value.finished, isTrue);
  });
  test('native checkpoint always owns resume despite old timestamp', () {
    final value = merged(nativeDate: oldDate.subtract(const Duration(days: 1)));
    expect(value.needsMigration, isFalse);
    expect(value.progression, .42);
  });
  test('v1 native checkpoint also owns resume', () {
    expect(merged().needsMigration, isFalse);
  });
  test('resource progression is never presented as book progression', () {
    final value = merged(
      nativeDate: newDate,
      locator: '{"href":"last.xhtml","locations":{"progression":1.0}}',
    );
    expect(value.needsMigration, isFalse);
    expect(value.progression, isNull);
    expect(value.progressLabel, '읽던 위치 저장됨');
  });
  test('invalid total ratio and malformed locator cannot poison library', () {
    expect(
      merged(
        nativeDate: newDate,
        locator: '{"href":"c","locations":{"totalProgression":5}}',
      ).progression,
      isNull,
    );
    expect(
      merged(nativeDate: newDate, locator: '{broken').needsMigration,
      isTrue,
    );
  });
  test('v1 native-only position remains resumable with unknown date', () {
    final result = mergeLibraryReadingStates(
      legacy: {},
      native: [
        const NativeLibraryPosition(
          publicationId: 'v1',
          locatorJson: '{"href":"chapter"}',
          lastOpenedAt: null,
        ),
      ],
      completion: {},
    );
    expect(result['v1']!.needsMigration, isFalse);
    expect(result['v1']!.lastReadAt, isNull);
  });
  test(
    'completion can be toggled without modifying a saved location',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = SharedPrefsLocalStorage();
      final reader = LegacyReaderArchive(storage);
      final completion = LibraryCompletionRepository(storage);
      await storage.setString(
        'reader_progress_book',
        progress('book', oldDate).toRaw(),
      );
      await completion.setFinished('book', true);
      expect((await completion.load())['book'], isTrue);
      await completion.setFinished('book', false);
      expect((await completion.load())['book'], isFalse);
      expect((await reader.loadProgress())['book']!.contentOffset, 500);
    },
  );
}
