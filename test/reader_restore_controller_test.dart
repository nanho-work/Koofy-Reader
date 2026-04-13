import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_restore_controller.dart';

void main() {
  group('ReaderRestoreController', () {
    test('resolveStoredOffset prefers anchor result', () {
      final progress = ReadingProgress(
        bookId: 'book',
        positionRatio: 0.4,
        contentOffset: 100,
        updatedAt: _epoch,
        anchor: const ReadingAnchor(
          chapterId: 'root',
          paragraphIndex: 1,
          charOffset: 2,
        ),
      );

      final resolved = ReaderRestoreController.resolveStoredOffset(
        progress: progress,
        contentLength: 1000,
        offsetFromAnchor: (_) => 222,
      );

      expect(resolved, 222);
    });

    test('resolveStoredOffset falls back to contentOffset', () {
      final progress = ReadingProgress(
        bookId: 'book',
        positionRatio: 0.4,
        contentOffset: 150,
        updatedAt: _epoch,
      );

      final resolved = ReaderRestoreController.resolveStoredOffset(
        progress: progress,
        contentLength: 1000,
        offsetFromAnchor: (_) => null,
      );

      expect(resolved, 150);
    });

    test('buildProgress clamps ratio and keeps anchor', () {
      const anchor = ReadingAnchor(
        chapterId: 'root',
        paragraphIndex: 3,
        charOffset: 7,
      );

      final progress = ReaderRestoreController.buildProgress(
        bookId: 'book',
        ratio: 1.5,
        contentOffset: 200,
        anchor: anchor,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      expect(progress.positionRatio, 1.0);
      expect(progress.contentOffset, 200);
      expect(progress.anchor, anchor);
    });
  });
}

final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);
