import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_spread_window_controller.dart';

void main() {
  group('ReaderSpreadWindowController', () {
    test('force start window begins near requested anchor', () {
      final content = List.generate(3000, (index) => 'a').join();
      final ranges = <ReaderParagraphRange>[
        ReaderParagraphRange(start: 0, end: content.length),
      ];

      final window = ReaderSpreadWindowController.buildWindow(
        content: content,
        paragraphRanges: ranges,
        anchorOffset: 1500,
        forceStartOffset: 1200,
      );

      expect(window.startOffset, 1200);
      expect(window.endOffset, greaterThan(window.startOffset));
    });

    test('window stays within content bounds', () {
      const content = 'para1\npara2\npara3\npara4\npara5';
      final index = ReaderContentIndexer.buildFromContent(content);

      final window = ReaderSpreadWindowController.buildWindow(
        content: content,
        paragraphRanges: index.paragraphRanges,
        anchorOffset: content.length,
      );

      expect(window.startOffset, greaterThanOrEqualTo(0));
      expect(window.endOffset, lessThanOrEqualTo(content.length));
      expect(window.content, isNotEmpty);
    });
  });
}
