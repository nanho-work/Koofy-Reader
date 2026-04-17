import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/core/services/reader_projection_service.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = ReaderProjectionService();

  test('clampSpreadStartIndex keeps even page boundaries', () {
    expect(service.clampSpreadStartIndex(3, 10), 2);
    expect(service.clampSpreadStartIndex(99, 7), 6);
  });

  test('mapSpreadIndexByOffset aligns to spread start', () {
    const pages = PaginatedText(
      source: 'abcdefghij',
      ranges: [
        TextPageRange(start: 0, end: 2),
        TextPageRange(start: 2, end: 4),
        TextPageRange(start: 4, end: 6),
        TextPageRange(start: 6, end: 8),
      ],
    );

    expect(service.mapSpreadIndexByOffset(pages, 1), 0);
    expect(service.mapSpreadIndexByOffset(pages, 3), 0);
    expect(service.mapSpreadIndexByOffset(pages, 5), 2);
  });

  test('containsOffset respects final content boundary', () {
    const pages = PaginatedText(
      source: 'abcdefghij',
      ranges: [
        TextPageRange(start: 0, end: 5),
        TextPageRange(start: 5, end: 10),
      ],
    );

    expect(
      service.containsOffset(pages: pages, offset: 9, contentLength: 10),
      isTrue,
    );
    expect(
      service.containsOffset(pages: pages, offset: 10, contentLength: 10),
      isTrue,
    );
    expect(
      service.containsOffset(pages: pages, offset: 11, contentLength: 10),
      isTrue,
    );
  });

  test('currentContentOffset prefers pinned double offset inside spread', () {
    const pages = PaginatedText(
      source: 'abcdefghij',
      ranges: [
        TextPageRange(start: 0, end: 2),
        TextPageRange(start: 2, end: 4),
        TextPageRange(start: 4, end: 6),
        TextPageRange(start: 6, end: 8),
      ],
    );

    final offset = service.currentContentOffset(
      content: pages.source,
      isDoubleActive: true,
      spreadPages: pages,
      currentSpreadStartIndex: 2,
      currentSingleContentOffset: 0,
      pinnedDoubleContentOffset: 5,
    );

    expect(offset, 5);
  });

  test('resolveStableAnchorOffset prefers pinned double offset', () {
    final offset = service.resolveStableAnchorOffset(
      content: 'abcdefghij',
      isDoubleActive: true,
      currentSingleContentOffset: 3,
      spreadPages: null,
      currentSpreadStartIndex: 0,
      pendingAnchorOffset: null,
      restoredContentOffset: 4,
      lastKnownContentOffset: 2,
      pinnedDoubleContentOffset: 7,
    );

    expect(offset, 7);
  });

  test('currentSpreadStartIndex keeps logical spread near settled row', () {
    const pages = PaginatedText(
      source: 'abcdefghijklmnop',
      ranges: [
        TextPageRange(start: 0, end: 2),
        TextPageRange(start: 2, end: 4),
        TextPageRange(start: 4, end: 6),
        TextPageRange(start: 6, end: 8),
        TextPageRange(start: 8, end: 10),
        TextPageRange(start: 10, end: 12),
      ],
    );

    final index = service.currentSpreadStartIndex(
      pages: pages,
      isSpreadJumping: false,
      spreadIndex: 2,
      hasSpreadClients: true,
      spreadViewportExtent: 633,
      spreadScrollOffset: 620,
    );

    expect(index, 2);
  });

  test('currentSpreadStartIndex rounds to nearest row when user moves away', () {
    const pages = PaginatedText(
      source: 'abcdefghijklmnop',
      ranges: [
        TextPageRange(start: 0, end: 2),
        TextPageRange(start: 2, end: 4),
        TextPageRange(start: 4, end: 6),
        TextPageRange(start: 6, end: 8),
        TextPageRange(start: 8, end: 10),
        TextPageRange(start: 10, end: 12),
      ],
    );

    final index = service.currentSpreadStartIndex(
      pages: pages,
      isSpreadJumping: false,
      spreadIndex: 2,
      hasSpreadClients: true,
      spreadViewportExtent: 633,
      spreadScrollOffset: 1700,
    );

    expect(index, 6 - 2);
  });

  test('singleScrollOffsetForContentOffset returns zero without painter', () {
    expect(
      service.singleScrollOffsetForContentOffset(
        content: 'abc',
        painter: null,
        contentOffset: 1,
        preserveRawOffset: false,
        hasScrollClients: false,
        maxScrollExtent: 0,
        singleViewportHeight: 100,
      ),
      0,
    );
  });

  test('currentSingleContentOffset can sample deeper into viewport', () {
    final content = List.filled(200, 'line of text').join('\n');
    final painter = TextPainter(
      text: const TextSpan(
        text: '',
        style: TextStyle(fontSize: 16, height: 1.6),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.text = const TextSpan(
      text: '',
      style: TextStyle(fontSize: 16, height: 1.6),
    );
    painter.text = TextSpan(
      text: content,
      style: const TextStyle(fontSize: 16, height: 1.6),
    );
    painter.layout(maxWidth: 320);

    final topOffset = service.currentSingleContentOffset(
      content: content,
      painter: painter,
      hasScrollClients: true,
      scrollOffset: 1200,
      maxScrollExtent: 4000,
      fallbackOffset: 0,
      singleViewportHeight: 700,
    );
    final centeredOffset = service.currentSingleContentOffset(
      content: content,
      painter: painter,
      hasScrollClients: true,
      scrollOffset: 1200,
      maxScrollExtent: 4000,
      fallbackOffset: 0,
      viewportBias: 0.42,
      singleViewportHeight: 700,
    );

    expect(centeredOffset, greaterThan(topOffset));
  });
}
