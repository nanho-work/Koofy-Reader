import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/core/services/reader_content_indexer.dart';

void main() {
  group('ReaderContentIndexer.buildParagraphBlocks', () {
    test('preserves original content when blocks are joined', () {
      const content = '첫줄\n\n둘째 문단\n셋째 문단';
      final index = ReaderContentIndexer.buildFromContent(content);

      final blocks = ReaderContentIndexer.buildParagraphBlocks(
        content,
        index.paragraphRanges,
      );

      expect(blocks.join(), content);
    });

    test('returns original content when paragraph ranges are empty', () {
      const content = '본문';

      final blocks = ReaderContentIndexer.buildParagraphBlocks(
        content,
        const <ReaderParagraphRange>[],
      );

      expect(blocks, <String>[content]);
    });
  });
}
