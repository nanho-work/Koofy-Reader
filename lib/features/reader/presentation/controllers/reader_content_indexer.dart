import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

class ReaderParagraphRange {
  const ReaderParagraphRange({required this.start, required this.end});

  final int start;
  final int end;
}

class ReaderChapterRange {
  const ReaderChapterRange({
    required this.id,
    required this.paragraphStartIndex,
    required this.paragraphEndIndex,
  });

  final String id;
  final int paragraphStartIndex;
  final int paragraphEndIndex;
}

class ReaderContentIndex {
  const ReaderContentIndex({
    required this.paragraphRanges,
    required this.chapterRanges,
  });

  final List<ReaderParagraphRange> paragraphRanges;
  final List<ReaderChapterRange> chapterRanges;
}

class ReaderContentIndexer {
  static final RegExp _chapterHeadingPattern = RegExp(
    r'^\s*(?:chapter\s+\d+|ch\.?\s*\d+|제\s*\d+\s*장|챕터\s*\d+|#\s+\S+)',
    caseSensitive: false,
  );

  static ReaderContentIndex fromContent(
    String content, {
    ReaderStructureIndex? structureIndex,
  }) {
    final indexed = applyStructureIndex(
      content: content,
      index: structureIndex,
    );
    if (indexed != null) {
      return indexed;
    }
    return buildFromContent(content);
  }

  static ReaderContentIndex buildFromContent(String content) {
    if (content.isEmpty) {
      return const ReaderContentIndex(
        paragraphRanges: <ReaderParagraphRange>[],
        chapterRanges: <ReaderChapterRange>[],
      );
    }

    final paragraphs = <ReaderParagraphRange>[];
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
      paragraphs.add(ReaderParagraphRange(start: start, end: end));
      start = end;
    }
    if (paragraphs.isEmpty) {
      paragraphs.add(ReaderParagraphRange(start: 0, end: content.length));
    }

    return ReaderContentIndex(
      paragraphRanges: paragraphs,
      chapterRanges: _buildChapterRanges(
        content: content,
        paragraphs: paragraphs,
      ),
    );
  }

  static ReaderContentIndex? applyStructureIndex({
    required String content,
    required ReaderStructureIndex? index,
  }) {
    if (index == null) {
      return null;
    }
    if (index.contentLength != content.length || index.paragraphs.isEmpty) {
      return null;
    }

    final paragraphs = <ReaderParagraphRange>[];
    for (final item in index.paragraphs) {
      final start = item.start.clamp(0, content.length);
      final end = item.end.clamp(start, content.length);
      if (end <= start) {
        continue;
      }
      paragraphs.add(ReaderParagraphRange(start: start, end: end));
    }
    if (paragraphs.isEmpty) {
      return null;
    }

    final chapters = <ReaderChapterRange>[];
    for (final item in index.chapters) {
      final start = item.paragraphStartIndex.clamp(0, paragraphs.length);
      final end = item.paragraphEndIndex.clamp(start, paragraphs.length);
      if (end <= start) {
        continue;
      }
      chapters.add(
        ReaderChapterRange(
          id: item.id,
          paragraphStartIndex: start,
          paragraphEndIndex: end,
        ),
      );
    }

    return ReaderContentIndex(
      paragraphRanges: paragraphs,
      chapterRanges: chapters.isEmpty
          ? [
              ReaderChapterRange(
                id: 'root',
                paragraphStartIndex: 0,
                paragraphEndIndex: paragraphs.length,
              ),
            ]
          : chapters,
    );
  }

  static int findParagraphIndexByOffset(
    List<ReaderParagraphRange> paragraphRanges,
    int offset,
  ) {
    if (paragraphRanges.isEmpty) {
      return 0;
    }
    int low = 0;
    int high = paragraphRanges.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      final range = paragraphRanges[mid];
      if (offset < range.end) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low.clamp(0, paragraphRanges.length - 1);
  }

  static ReadingAnchor buildAnchorForOffset({
    required int offset,
    required int contentLength,
    required List<ReaderParagraphRange> paragraphRanges,
    required List<ReaderChapterRange> chapterRanges,
  }) {
    final clamped = offset.clamp(0, contentLength);
    if (paragraphRanges.isEmpty) {
      return ReadingAnchor(
        chapterId: 'root',
        paragraphIndex: 0,
        charOffset: clamped,
      );
    }

    final paragraphIndex = findParagraphIndexByOffset(paragraphRanges, clamped);
    final paragraph = paragraphRanges[paragraphIndex];
    final charOffset = (clamped - paragraph.start).clamp(
      0,
      paragraph.end - paragraph.start,
    );

    ReaderChapterRange? chapter;
    for (final current in chapterRanges) {
      if (paragraphIndex >= current.paragraphStartIndex &&
          paragraphIndex < current.paragraphEndIndex) {
        chapter = current;
        break;
      }
    }
    chapter ??= chapterRanges.isNotEmpty ? chapterRanges.last : null;
    final chapterId = chapter?.id ?? 'root';
    final chapterParagraphStart = chapter?.paragraphStartIndex ?? 0;
    final localParagraphIndex = (paragraphIndex - chapterParagraphStart).clamp(
      0,
      1 << 30,
    );

    return ReadingAnchor(
      chapterId: chapterId,
      paragraphIndex: localParagraphIndex,
      charOffset: charOffset,
    );
  }

  static int? offsetFromAnchor({
    required ReadingAnchor? anchor,
    required List<ReaderParagraphRange> paragraphRanges,
    required List<ReaderChapterRange> chapterRanges,
  }) {
    if (anchor == null || paragraphRanges.isEmpty) {
      return null;
    }
    ReaderChapterRange? chapter;
    for (final candidate in chapterRanges) {
      if (candidate.id == anchor.chapterId) {
        chapter = candidate;
        break;
      }
    }
    chapter ??= chapterRanges.isNotEmpty ? chapterRanges.first : null;
    final chapterStart = chapter?.paragraphStartIndex ?? 0;
    final chapterEnd = chapter?.paragraphEndIndex ?? paragraphRanges.length;
    final chapterCount = (chapterEnd - chapterStart).clamp(1, 1 << 30);
    final localParagraph = anchor.paragraphIndex.clamp(0, chapterCount - 1);
    final paragraphIndex = (chapterStart + localParagraph).clamp(
      0,
      paragraphRanges.length - 1,
    );
    final paragraph = paragraphRanges[paragraphIndex];
    final raw = paragraph.start + anchor.charOffset;
    return raw.clamp(paragraph.start, paragraph.end);
  }

  static List<ReaderChapterRange> _buildChapterRanges({
    required String content,
    required List<ReaderParagraphRange> paragraphs,
  }) {
    if (paragraphs.isEmpty) {
      return const <ReaderChapterRange>[];
    }

    final markers = _collectChapterMarkers(content);
    if (markers.isEmpty) {
      return [
        ReaderChapterRange(
          id: 'root',
          paragraphStartIndex: 0,
          paragraphEndIndex: paragraphs.length,
        ),
      ];
    }

    final seeds = <_ReaderChapterMarker>[];
    if (markers.first.startOffset > 0) {
      seeds.add(const _ReaderChapterMarker(id: 'intro', startOffset: 0));
    }
    seeds.addAll(markers);

    final ranges = <ReaderChapterRange>[];
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
        ReaderChapterRange(
          id: seeds[i].id,
          paragraphStartIndex: paragraphStart,
          paragraphEndIndex: paragraphEnd,
        ),
      );
    }

    if (ranges.isEmpty) {
      return [
        ReaderChapterRange(
          id: 'root',
          paragraphStartIndex: 0,
          paragraphEndIndex: paragraphs.length,
        ),
      ];
    }
    return ranges;
  }

  static List<_ReaderChapterMarker> _collectChapterMarkers(String content) {
    final markers = <_ReaderChapterMarker>[];
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
          _ReaderChapterMarker(id: 'ch_$chapterIndex', startOffset: lineStart),
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

  static int _firstParagraphIndexAtOrAfter({
    required List<ReaderParagraphRange> paragraphs,
    required int offset,
  }) {
    if (paragraphs.isEmpty) {
      return 0;
    }
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

class _ReaderChapterMarker {
  const _ReaderChapterMarker({required this.id, required this.startOffset});

  final String id;
  final int startOffset;
}
