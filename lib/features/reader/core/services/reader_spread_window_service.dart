import 'package:koofy_reader/features/reader/core/services/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/core/services/reader_position_service.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';

class ReaderPaginationWindow {
  const ReaderPaginationWindow({
    required this.startOffset,
    required this.endOffset,
    required this.content,
  });

  final int startOffset;
  final int endOffset;
  final String content;
}

class ReaderSpreadWindowService {
  const ReaderSpreadWindowService._();

  static const int doubleWindowBeforeParagraphs = 16;
  static const int doubleWindowAfterParagraphs = 28;
  static const int _windowMinCharsDefault = 7000;
  static const int _windowMaxCharsDefault = 24000;
  static const int _newlineScanExtraChars = 512;

  static int _windowMinCharsForLength(int contentLength) {
    if (contentLength >= 400000) {
      return 5000;
    }
    if (contentLength >= 200000) {
      return 6000;
    }
    return _windowMinCharsDefault;
  }

  static int _windowMaxCharsForLength(int contentLength) {
    if (contentLength >= 400000) {
      return 12000;
    }
    if (contentLength >= 200000) {
      return 16000;
    }
    return _windowMaxCharsDefault;
  }

  static int windowMinCharsForLength(int contentLength) {
    return _windowMinCharsForLength(contentLength);
  }

  static ReaderPaginationWindow buildWindow({
    required String content,
    required List<ReaderParagraphRange> paragraphRanges,
    required int anchorOffset,
    int? forceStartOffset,
  }) {
    if (content.isEmpty) {
      return ReaderPaginationWindow(
        startOffset: 0,
        endOffset: content.length,
        content: content,
      );
    }

    final minChars = _windowMinCharsForLength(content.length);
    final maxChars = _windowMaxCharsForLength(content.length);
    final beforeParagraphs = content.length >= 200000
        ? 10
        : doubleWindowBeforeParagraphs;
    final afterParagraphs = content.length >= 200000
        ? 18
        : doubleWindowAfterParagraphs;
    final normalizedAnchor = anchorOffset.clamp(0, content.length);

    if (paragraphRanges.isEmpty) {
      return _buildFlatWindowWithoutParagraphs(
        content: content,
        anchorOffset: normalizedAnchor,
        minChars: minChars,
        maxChars: maxChars,
      );
    }

    if (forceStartOffset != null) {
      final startOffset = ReaderPositionService.normalizeRestoreOffset(
        content: content,
        offset: forceStartOffset,
        doubleMode: true,
      ).clamp(0, content.length);
      var endOffset = (startOffset + maxChars).clamp(
        startOffset,
        content.length,
      );
      final minimumEnd = (startOffset + minChars).clamp(
        startOffset,
        content.length,
      );
      if (endOffset < minimumEnd) {
        endOffset = minimumEnd;
      }
      endOffset = _extendWindowEndToLineBoundary(
        content: content,
        endOffset: endOffset,
      );
      if (endOffset <= startOffset) {
        endOffset = (startOffset + minChars).clamp(
          startOffset + 1,
          content.length,
        );
      }
      return ReaderPaginationWindow(
        startOffset: startOffset,
        endOffset: endOffset,
        content: content.substring(startOffset, endOffset),
      );
    }

    final centerParagraph = ReaderContentIndexer.findParagraphIndexByOffset(
      paragraphRanges,
      normalizedAnchor,
    );
    var startParagraph = (centerParagraph - beforeParagraphs).clamp(
      0,
      paragraphRanges.length - 1,
    );
    var endParagraph = (centerParagraph + afterParagraphs).clamp(
      0,
      paragraphRanges.length - 1,
    );

    var startOffset = paragraphRanges[startParagraph].start;
    var endOffset = paragraphRanges[endParagraph].end;

    while ((endOffset - startOffset) < minChars &&
        (startParagraph > 0 || endParagraph < paragraphRanges.length - 1)) {
      if (startParagraph > 0) {
        startParagraph--;
        startOffset = paragraphRanges[startParagraph].start;
      }
      if ((endOffset - startOffset) >= minChars) {
        break;
      }
      if (endParagraph < paragraphRanges.length - 1) {
        endParagraph++;
        endOffset = paragraphRanges[endParagraph].end;
      }
    }

    if ((endOffset - startOffset) > maxChars) {
      startOffset = ReaderPositionService.normalizeToLineStartOffset(
        content: content,
        offset: (normalizedAnchor - (maxChars ~/ 3)).clamp(0, content.length),
      );
      endOffset = (startOffset + maxChars).clamp(startOffset, content.length);
      endOffset = _extendWindowEndToLineBoundary(
        content: content,
        endOffset: endOffset,
      );
    }

    if (endOffset <= startOffset) {
      final fallback = _buildFlatWindowWithoutParagraphs(
        content: content,
        anchorOffset: normalizedAnchor,
        minChars: minChars,
        maxChars: maxChars,
      );
      startOffset = fallback.startOffset;
      endOffset = fallback.endOffset;
    }

    return ReaderPaginationWindow(
      startOffset: startOffset,
      endOffset: endOffset,
      content: content.substring(startOffset, endOffset),
    );
  }

  static ReaderPaginationWindow _buildFlatWindowWithoutParagraphs({
    required String content,
    required int anchorOffset,
    required int minChars,
    required int maxChars,
  }) {
    final startOffset = ReaderPositionService.normalizeToLineStartOffset(
      content: content,
      offset: (anchorOffset - (maxChars ~/ 3)).clamp(0, content.length),
    );
    var endOffset = (startOffset + maxChars).clamp(startOffset, content.length);
    final minimumEnd = (startOffset + minChars).clamp(
      startOffset,
      content.length,
    );
    if (endOffset < minimumEnd) {
      endOffset = minimumEnd;
    }
    endOffset = _extendWindowEndToLineBoundary(
      content: content,
      endOffset: endOffset,
    );
    if (endOffset <= startOffset) {
      endOffset = (startOffset + minChars).clamp(
        startOffset + 1,
        content.length,
      );
    }
    return ReaderPaginationWindow(
      startOffset: startOffset,
      endOffset: endOffset,
      content: content.substring(startOffset, endOffset),
    );
  }

  static int _extendWindowEndToLineBoundary({
    required String content,
    required int endOffset,
  }) {
    if (endOffset >= content.length) {
      return content.length;
    }
    final limit = (endOffset + _newlineScanExtraChars).clamp(
      endOffset,
      content.length,
    );
    var cursor = endOffset;
    while (cursor < limit && content.codeUnitAt(cursor) != 0x0A) {
      cursor++;
    }
    if (cursor < content.length && content.codeUnitAt(cursor) == 0x0A) {
      return cursor;
    }
    return endOffset;
  }

  static PaginatedText toGlobalPaginatedText({
    required PaginatedText localPages,
    required int windowStartOffset,
    required String sourceContent,
  }) {
    if (windowStartOffset <= 0 || localPages.ranges.isEmpty) {
      return localPages;
    }
    final globalRanges = localPages.ranges
        .map(
          (range) => TextPageRange(
            start: range.start + windowStartOffset,
            end: range.end + windowStartOffset,
          ),
        )
        .toList(growable: false);
    return PaginatedText(source: sourceContent, ranges: globalRanges);
  }
}
