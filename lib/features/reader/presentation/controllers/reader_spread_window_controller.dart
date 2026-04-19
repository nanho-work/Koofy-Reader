import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_position_controller.dart';

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

class ReaderSpreadWindowController {
  const ReaderSpreadWindowController._();

  static const int doubleWindowBeforeParagraphs = 16;
  static const int doubleWindowAfterParagraphs = 28;
  static const int doubleWindowMinChars = 7000;
  static const int doubleWindowMaxChars = 24000;

  static ReaderPaginationWindow buildWindow({
    required String content,
    required List<ReaderParagraphRange> paragraphRanges,
    required int anchorOffset,
    int? forceStartOffset,
  }) {
    if (content.isEmpty || paragraphRanges.isEmpty) {
      return ReaderPaginationWindow(
        startOffset: 0,
        endOffset: content.length,
        content: content,
      );
    }

    if (forceStartOffset != null) {
      final startOffset = ReaderPositionController.normalizeRestoreOffset(
        content: content,
        offset: forceStartOffset,
        doubleMode: true,
      ).clamp(0, content.length);
      var endOffset = (startOffset + doubleWindowMaxChars).clamp(
        startOffset,
        content.length,
      );
      final minimumEnd = (startOffset + doubleWindowMinChars).clamp(
        startOffset,
        content.length,
      );
      if (endOffset < minimumEnd) {
        endOffset = minimumEnd;
      }
      while (endOffset < content.length &&
          content.codeUnitAt(endOffset) != 0x0A) {
        endOffset++;
      }
      if (endOffset <= startOffset) {
        endOffset = content.length;
      }
      return ReaderPaginationWindow(
        startOffset: startOffset,
        endOffset: endOffset,
        content: content.substring(startOffset, endOffset),
      );
    }

    final centerParagraph = ReaderContentIndexer.findParagraphIndexByOffset(
      paragraphRanges,
      anchorOffset.clamp(0, content.length),
    );
    var startParagraph = (centerParagraph - doubleWindowBeforeParagraphs).clamp(
      0,
      paragraphRanges.length - 1,
    );
    var endParagraph = (centerParagraph + doubleWindowAfterParagraphs).clamp(
      0,
      paragraphRanges.length - 1,
    );

    var startOffset = paragraphRanges[startParagraph].start;
    var endOffset = paragraphRanges[endParagraph].end;

    while ((endOffset - startOffset) < doubleWindowMinChars &&
        (startParagraph > 0 || endParagraph < paragraphRanges.length - 1)) {
      if (startParagraph > 0) {
        startParagraph--;
        startOffset = paragraphRanges[startParagraph].start;
      }
      if ((endOffset - startOffset) >= doubleWindowMinChars) {
        break;
      }
      if (endParagraph < paragraphRanges.length - 1) {
        endParagraph++;
        endOffset = paragraphRanges[endParagraph].end;
      }
    }

    if ((endOffset - startOffset) > doubleWindowMaxChars) {
      startOffset = ReaderPositionController.normalizeToLineStartOffset(
        content: content,
        offset: (anchorOffset - (doubleWindowMaxChars ~/ 3)).clamp(
          0,
          content.length,
        ),
      );
      endOffset = (startOffset + doubleWindowMaxChars).clamp(
        startOffset,
        content.length,
      );
      while (endOffset < content.length &&
          content.codeUnitAt(endOffset) != 0x0A) {
        endOffset++;
      }
    }

    if (endOffset <= startOffset) {
      startOffset = 0;
      endOffset = content.length;
    }

    return ReaderPaginationWindow(
      startOffset: startOffset,
      endOffset: endOffset,
      content: content.substring(startOffset, endOffset),
    );
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
