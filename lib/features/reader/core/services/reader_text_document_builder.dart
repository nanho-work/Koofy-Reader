import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';

class ReaderTextDocumentBuilder {
  const ReaderTextDocumentBuilder();

  ReaderTextDocument build({
    required String content,
    ReaderStructureIndex? structureIndex,
  }) {
    return ReaderTextDocument.fromContent(
      content,
      structureIndex: structureIndex,
    );
  }
}
