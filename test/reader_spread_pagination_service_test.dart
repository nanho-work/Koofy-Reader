import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/core/services/reader_spread_pagination_service.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_layout_controller.dart';

void main() {
  final layout = ReaderLayoutController(
    settings: ReaderSettings.defaults().copyWith(
      pageLayoutMode: ReaderPageLayoutMode.double,
    ),
  );
  const mediaQueryData = MediaQueryData();
  const viewport = Size(900, 700);
  const style = TextStyle(fontSize: 18, height: 1.7);
  final layoutSignature = layout.paginationSignature(
    viewport,
    mediaQueryData: mediaQueryData,
  );
  final textArea = layout.textAreaForPagination(
    viewport,
    mediaQueryData: mediaQueryData,
  );

  ReaderTextDocument buildDocument() {
    final paragraph = List.filled(40, 'lorem ipsum dolor sit amet').join(' ');
    final content = List.generate(
      260,
      (index) => '[$index] $paragraph',
    ).join('\n');
    return ReaderTextDocument.fromContent(content);
  }

  bool spreadContainsAnchor({
    required int anchorOffset,
    required int mappedIndex,
    required List ranges,
  }) {
    final left = ranges[mappedIndex];
    final rightIndex = mappedIndex + 1 < ranges.length
        ? mappedIndex + 1
        : mappedIndex;
    final right = ranges[rightIndex];
    return anchorOffset >= left.start && anchorOffset < right.end;
  }

  test('paginate keeps requested anchor inside mapped spread', () async {
    final service = ReaderSpreadPaginationService();
    final document = buildDocument();
    final anchorOffset = document.length - 800;

    final result = await service.paginate(
      document: document,
      layoutSignature: layoutSignature,
      textArea: textArea,
      style: style,
      anchorOffset: anchorOffset,
    );

    expect(result.windowStartOffset, greaterThan(0));
    expect(
      spreadContainsAnchor(
        anchorOffset: anchorOffset,
        mappedIndex: result.mappedIndex,
        ranges: result.pages.ranges,
      ),
      isTrue,
    );
  });

  test('paginate reuses cached spread pages for the same window', () async {
    final service = ReaderSpreadPaginationService();
    final document = buildDocument();
    final anchorOffset = document.length ~/ 2;

    final first = await service.paginate(
      document: document,
      layoutSignature: layoutSignature,
      textArea: textArea,
      style: style,
      anchorOffset: anchorOffset,
    );
    final second = await service.paginate(
      document: document,
      layoutSignature: layoutSignature,
      textArea: textArea,
      style: style,
      anchorOffset: anchorOffset,
    );

    expect(first.fromCache, isFalse);
    expect(second.fromCache, isTrue);
    expect(second.signature, first.signature);
    expect(second.mappedIndex, first.mappedIndex);
  });

  test(
    'paginate falls back to a targeted window when primary mapping misses',
    () async {
      final engine = _FallbackPaginationEngine();
      final service = ReaderSpreadPaginationService(engine: engine);
      final document = buildDocument();
      final anchorOffset = document.length - 1200;

      final result = await service.paginate(
        document: document,
        layoutSignature: layoutSignature,
        textArea: textArea,
        style: style,
        anchorOffset: anchorOffset,
      );

      expect(engine.calls, 2);
      expect(result.usedFallbackWindow, isTrue);
      expect(
        spreadContainsAnchor(
          anchorOffset: anchorOffset,
          mappedIndex: result.mappedIndex,
          ranges: result.pages.ranges,
        ),
        isTrue,
      );
    },
  );
}

class _FallbackPaginationEngine extends TextPaginationEngine {
  int calls = 0;

  @override
  Future<PaginatedText> paginateAsync({
    required String content,
    required double maxWidth,
    required double maxHeight,
    required TextStyle style,
    int yieldEvery = 20,
    int? maxPages,
  }) async {
    calls += 1;
    if (content.isEmpty) {
      return const PaginatedText(
        source: '',
        ranges: [TextPageRange(start: 0, end: 0)],
      );
    }
    if (calls == 1) {
      final shortEnd = (content.length ~/ 4).clamp(1, content.length);
      return PaginatedText(
        source: content,
        ranges: [TextPageRange(start: 0, end: shortEnd)],
      );
    }
    final midpoint = (content.length ~/ 2).clamp(1, content.length);
    return PaginatedText(
      source: content,
      ranges: [
        TextPageRange(start: 0, end: midpoint),
        TextPageRange(start: midpoint, end: content.length),
      ],
    );
  }
}
