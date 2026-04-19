import 'package:koofy_reader/core/utils/hash_utils.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/core/services/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';

class ReaderDocumentEngine {
  const ReaderDocumentEngine();

  String normalizeContent(String rawContent) {
    return rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  String stableHash(String value) {
    return HashUtils.fnv1a32(value);
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
