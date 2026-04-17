import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/core/services/reader_content_indexer.dart';

class ReaderTextDocument {
  const ReaderTextDocument({
    required this.content,
    required this.paragraphRanges,
    required this.chapterRanges,
  });

  factory ReaderTextDocument.fromContent(
    String content, {
    ReaderStructureIndex? structureIndex,
  }) {
    final indexed = ReaderContentIndexer.fromContent(
      content,
      structureIndex: structureIndex,
    );
    return ReaderTextDocument(
      content: content,
      paragraphRanges: indexed.paragraphRanges,
      chapterRanges: indexed.chapterRanges,
    );
  }

  final String content;
  final List<ReaderParagraphRange> paragraphRanges;
  final List<ReaderChapterRange> chapterRanges;

  int get length => content.length;

  ReadingAnchor buildAnchorForOffset(int offset) {
    return ReaderContentIndexer.buildAnchorForOffset(
      offset: offset,
      contentLength: content.length,
      paragraphRanges: paragraphRanges,
      chapterRanges: chapterRanges,
    );
  }

  int? offsetFromAnchor(ReadingAnchor? anchor) {
    return ReaderContentIndexer.offsetFromAnchor(
      anchor: anchor,
      paragraphRanges: paragraphRanges,
      chapterRanges: chapterRanges,
    );
  }

  int findParagraphIndexByOffset(int offset) {
    return ReaderContentIndexer.findParagraphIndexByOffset(
      paragraphRanges,
      offset,
    );
  }

  List<int> searchOffsets(String query, {int limit = 1000}) {
    if (content.isEmpty) {
      return const <int>[];
    }

    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <int>[];
    }

    final haystack = content.toLowerCase();
    final offsets = <int>[];
    int cursor = 0;
    while (cursor < haystack.length) {
      final found = haystack.indexOf(needle, cursor);
      if (found < 0) {
        break;
      }
      offsets.add(found);
      if (offsets.length >= limit) {
        break;
      }
      cursor = found + needle.length;
    }
    return offsets;
  }
}
