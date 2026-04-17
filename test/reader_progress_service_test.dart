import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/core/services/reader_progress_service.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

void main() {
  const service = ReaderProgressService();
  final document = ReaderTextDocument.fromContent(
    'a\nparagraph one\nparagraph two',
  );

  test('resolveOffset prefers anchor over contentOffset', () {
    final progress = ReadingProgress(
      bookId: 'book',
      positionRatio: 0.5,
      contentOffset: 1,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      anchor: const ReadingAnchor(
        chapterId: 'root',
        paragraphIndex: 1,
        charOffset: 3,
      ),
    );

    final resolved = service.resolveOffset(
      document: document,
      progress: progress,
    );

    expect(resolved, 5);
  });

  test(
    'resolveOffset prefers locator global offset over anchor and contentOffset',
    () {
      final progress = ReadingProgress(
        bookId: 'book',
        positionRatio: 0.1,
        contentOffset: 1,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        anchor: const ReadingAnchor(
          chapterId: 'root',
          paragraphIndex: 0,
          charOffset: 0,
        ),
        locator: const ReadingLocator(
          chapterId: 'root',
          paragraphIndex: 2,
          charOffset: 3,
          globalOffset: 20,
          progression: 0.8,
        ),
      );

      final resolved = service.resolveOffset(
        document: document,
        progress: progress,
      );

      expect(resolved, 20);
    },
  );

  test(
    'resolveOffset falls back to ratio when anchor and offset are unusable',
    () {
      final progress = ReadingProgress(
        bookId: 'book',
        positionRatio: 0.5,
        contentOffset: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final resolved = service.resolveOffset(
        document: document,
        progress: progress,
      );

      expect(resolved, 15);
    },
  );

  test('buildProgress creates anchor from document offset', () {
    final progress = service.buildProgress(
      bookId: 'book',
      document: document,
      contentOffset: 16,
      doublePageStartOffset: 12,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    expect(progress.contentOffset, 16);
    expect(progress.doublePageStartOffset, 12);
    expect(progress.anchor, isNotNull);
    expect(progress.anchor!.chapterId, 'root');
    expect(progress.anchor!.paragraphIndex, 2);
    expect(progress.locator, isNotNull);
    expect(progress.locator!.globalOffset, 16);
  });

  test('resolveDoublePageStartOffset returns persisted visual hint', () {
    final progress = ReadingProgress(
      bookId: 'book',
      positionRatio: 0.5,
      contentOffset: 16,
      doublePageStartOffset: 12,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    final resolved = service.resolveDoublePageStartOffset(
      document: document,
      progress: progress,
    );

    expect(resolved, 12);
  });
}
