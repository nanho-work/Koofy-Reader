import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/core/services/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';

class ReaderDocumentEngine {
  const ReaderDocumentEngine();

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
    final contentIndex = ReaderContentIndexer.buildFromContent(content);
    final paragraphs = contentIndex.paragraphRanges
        .map(
          (range) =>
              ReaderParagraphRangeData(start: range.start, end: range.end),
        )
        .toList(growable: false);
    final chapters = contentIndex.chapterRanges
        .map(
          (range) => ReaderChapterRangeData(
            id: range.id,
            paragraphStartIndex: range.paragraphStartIndex,
            paragraphEndIndex: range.paragraphEndIndex,
          ),
        )
        .toList(growable: false);

    return ReaderStructureIndex(
      schemaVersion: ReaderStructureIndex.currentSchemaVersion,
      contentLength: content.length,
      contentHash: contentHash,
      paragraphs: paragraphs,
      chapters: chapters,
    );
  }
}
