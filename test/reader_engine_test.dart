import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/engine/reader_engine.dart';

void main() {
  group('ReaderEngine', () {
    const engine = ReaderEngine();

    test('normalize/build/resolve stored offset keeps canonical locator', () {
      const raw = '첫줄\r\n둘째줄\r셋째줄';
      final normalized = engine.normalizeContent(raw);
      final hash = engine.stableHash(normalized);
      final structureIndex = engine.buildStructureIndex(
        content: normalized,
        contentHash: hash,
      );
      final document = engine.buildDocument(
        content: normalized,
        structureIndex: structureIndex,
      );

      final progress = engine.buildProgress(
        bookId: 'book',
        document: document,
        contentOffset: 3,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final resolved = engine.resolveStoredOffset(
        document: document,
        progress: progress,
      );

      expect(normalized, '첫줄\n둘째줄\n셋째줄');
      expect(resolved, 3);
    });

    test('search returns locator-aware results', () {
      final document = engine.buildDocument(content: 'alpha beta alpha');

      final results = engine.search(document: document, query: 'alpha');

      expect(results, hasLength(2));
      expect(results.first.locator.globalOffset, 0);
      expect(results.last.locator.globalOffset, 11);
    });

    test('offsetFromLocator falls back to anchor-aware lookup', () {
      final document = engine.buildDocument(content: 'abc\ndef');
      const locator = ReadingLocator(
        chapterId: 'root',
        paragraphIndex: 1,
        charOffset: 1,
        globalOffset: 99,
        progression: 0.5,
      );

      final resolved = engine.offsetFromLocator(
        document: document,
        locator: locator,
      );

      expect(resolved, 5);
    });

    test('structure index and document share the same chapter rules', () {
      const content = '프롤로그\n제 1 장 시작\n본문 첫줄\n제 2 장 다음\n본문 둘째';
      final structureIndex = engine.buildStructureIndex(
        content: content,
        contentHash: engine.stableHash(content),
      );
      final indexedDocument = engine.buildDocument(
        content: content,
        structureIndex: structureIndex,
      );
      final directDocument = engine.buildDocument(content: content);

      final indexedAnchor = indexedDocument.buildAnchorForOffset(18);
      final directAnchor = directDocument.buildAnchorForOffset(18);

      expect(indexedAnchor.chapterId, directAnchor.chapterId);
      expect(indexedAnchor.paragraphIndex, directAnchor.paragraphIndex);
      expect(indexedAnchor.charOffset, directAnchor.charOffset);
      expect(
        structureIndex.chapters.map((item) => item.id),
        containsAll(<String>['intro', 'ch_1', 'ch_2']),
      );
    });
  });
}
