import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';

class ReaderDocumentEngine {
  const ReaderDocumentEngine();

  static final RegExp _chapterHeadingPattern = RegExp(
    r'^\s*(?:chapter\s+\d+|ch\.?\s*\d+|제\s*\d+\s*장|챕터\s*\d+|#\s+\S+)',
    caseSensitive: false,
  );

  String normalizeContent(String rawContent) {
    return rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  String stableHash(String value) {
    const int fnvOffsetBasis = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffsetBasis;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  ReaderTextDocument buildDocument({
    required String content,
    ReaderStructureIndex? structureIndex,
  }) {
    return ReaderTextDocument.fromContent(
      content,
      structureIndex: structureIndex,
    );
  }

  ReaderStructureIndex buildStructureIndex({
    required String content,
    required String contentHash,
  }) {
    final paragraphs = <ReaderParagraphRangeData>[];
    int start = 0;
    while (start < content.length) {
      while (start < content.length && content.codeUnitAt(start) == 0x0A) {
        start++;
      }
      if (start >= content.length) {
        break;
      }
      int end = start;
      while (end < content.length && content.codeUnitAt(end) != 0x0A) {
        end++;
      }
      paragraphs.add(ReaderParagraphRangeData(start: start, end: end));
      start = end;
    }
    if (paragraphs.isEmpty) {
      paragraphs.add(
        ReaderParagraphRangeData(
          start: 0,
          end: content.length.clamp(0, 1 << 30),
        ),
      );
    }

    return ReaderStructureIndex(
      schemaVersion: ReaderStructureIndex.currentSchemaVersion,
      contentLength: content.length,
      contentHash: contentHash,
      paragraphs: paragraphs,
      chapters: _buildChapterRanges(content: content, paragraphs: paragraphs),
    );
  }

  List<ReaderChapterRangeData> _buildChapterRanges({
    required String content,
    required List<ReaderParagraphRangeData> paragraphs,
  }) {
    if (paragraphs.isEmpty) {
      return const <ReaderChapterRangeData>[];
    }

    final markers = _collectChapterMarkers(content);
    if (markers.isEmpty) {
      return [
        ReaderChapterRangeData(
          id: 'root',
          paragraphStartIndex: 0,
          paragraphEndIndex: paragraphs.length,
        ),
      ];
    }

    final seeds = <_ChapterMarkerSeed>[];
    if (markers.first.startOffset > 0) {
      seeds.add(const _ChapterMarkerSeed(id: 'intro', startOffset: 0));
    }
    seeds.addAll(markers);

    final ranges = <ReaderChapterRangeData>[];
    for (int i = 0; i < seeds.length; i++) {
      final startOffset = seeds[i].startOffset;
      final endOffset = (i + 1 < seeds.length)
          ? seeds[i + 1].startOffset
          : content.length;
      final paragraphStart = _firstParagraphIndexAtOrAfter(
        paragraphs: paragraphs,
        offset: startOffset,
      );
      final paragraphEnd = _firstParagraphIndexAtOrAfter(
        paragraphs: paragraphs,
        offset: endOffset,
      );
      if (paragraphStart >= paragraphEnd) {
        continue;
      }
      ranges.add(
        ReaderChapterRangeData(
          id: seeds[i].id,
          paragraphStartIndex: paragraphStart,
          paragraphEndIndex: paragraphEnd,
        ),
      );
    }

    if (ranges.isEmpty) {
      return [
        ReaderChapterRangeData(
          id: 'root',
          paragraphStartIndex: 0,
          paragraphEndIndex: paragraphs.length,
        ),
      ];
    }
    return ranges;
  }

  List<_ChapterMarkerSeed> _collectChapterMarkers(String content) {
    final markers = <_ChapterMarkerSeed>[];
    int lineStart = 0;
    int chapterIndex = 1;

    while (lineStart <= content.length) {
      int lineEnd = content.indexOf('\n', lineStart);
      if (lineEnd == -1) {
        lineEnd = content.length;
      }
      final line = content.substring(lineStart, lineEnd);
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && _chapterHeadingPattern.hasMatch(trimmed)) {
        markers.add(
          _ChapterMarkerSeed(id: 'ch_$chapterIndex', startOffset: lineStart),
        );
        chapterIndex++;
      }
      if (lineEnd >= content.length) {
        break;
      }
      lineStart = lineEnd + 1;
    }

    return markers;
  }

  int _firstParagraphIndexAtOrAfter({
    required List<ReaderParagraphRangeData> paragraphs,
    required int offset,
  }) {
    int low = 0;
    int high = paragraphs.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (paragraphs[mid].start < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low.clamp(0, paragraphs.length);
  }
}

class _ChapterMarkerSeed {
  const _ChapterMarkerSeed({required this.id, required this.startOffset});

  final String id;
  final int startOffset;
}
