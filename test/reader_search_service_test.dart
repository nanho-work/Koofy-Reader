import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/core/services/reader_search_service.dart';

void main() {
  const service = ReaderSearchService();

  ReaderTextDocument buildDocument() {
    final content = [
      'Chapter 1',
      'The quick brown fox jumps over the lazy dog.',
      'Search should return a stable locator.',
      'Another quick match appears here.',
    ].join('\n');
    return ReaderTextDocument.fromContent(content);
  }

  test('search returns locator-aware results', () {
    final document = buildDocument();

    final results = service.search(document: document, query: 'quick');

    expect(results, hasLength(2));
    expect(results.first.offset, greaterThan(0));
    expect(results.first.anchor.chapterId, 'ch_1');
    expect(results.first.locator.globalOffset, results.first.offset);
    expect(
      results.first.locator.paragraphIndex,
      results.first.anchor.paragraphIndex,
    );
  });

  test('search excerpt includes surrounding text and ellipsis when needed', () {
    final excerpt = ReaderSearchService.buildExcerpt(
      source: '0123456789 abcdefghijklmnopqrstuvwxyz 9876543210',
      offset: 12,
      query: 'abc',
      radius: 6,
    );

    expect(excerpt, contains('abc'));
    expect(excerpt.startsWith('...'), isTrue);
    expect(excerpt.endsWith('...'), isTrue);
  });

  test('normalizeHistory keeps newest unique search terms first', () {
    final normalized = service.normalizeHistory([
      'Quick',
      'fox',
      'quick',
      ' locator ',
    ]);

    expect(normalized, ['Quick', 'fox', 'locator']);
  });

  test('search respects non-positive limit', () {
    final document = buildDocument();

    final results = service.search(
      document: document,
      query: 'quick',
      limit: 0,
    );

    expect(results, isEmpty);
  });
}
