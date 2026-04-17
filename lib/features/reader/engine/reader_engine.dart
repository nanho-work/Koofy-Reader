import 'package:koofy_reader/features/reader/core/models/reader_search_result.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/core/services/reader_progress_service.dart';
import 'package:koofy_reader/features/reader/core/services/reader_search_service.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/engine/reader_document_engine.dart';

class ReaderEngine {
  const ReaderEngine({
    ReaderDocumentEngine? documentEngine,
    ReaderProgressService? progressService,
    ReaderSearchService? searchService,
  }) : _documentEngine = documentEngine ?? const ReaderDocumentEngine(),
       _progressService = progressService ?? const ReaderProgressService(),
       _searchService = searchService ?? const ReaderSearchService();

  final ReaderDocumentEngine _documentEngine;
  final ReaderProgressService _progressService;
  final ReaderSearchService _searchService;

  String normalizeContent(String rawContent) {
    return _documentEngine.normalizeContent(rawContent);
  }

  String stableHash(String content) {
    return _documentEngine.stableHash(content);
  }

  ReaderStructureIndex buildStructureIndex({
    required String content,
    required String contentHash,
  }) {
    return _documentEngine.buildStructureIndex(
      content: content,
      contentHash: contentHash,
    );
  }

  ReaderTextDocument buildDocument({
    required String content,
    ReaderStructureIndex? structureIndex,
  }) {
    return _documentEngine.buildDocument(
      content: content,
      structureIndex: structureIndex,
    );
  }

  ReadingAnchor buildAnchorForOffset({
    required ReaderTextDocument? document,
    required int offset,
  }) {
    if (document == null || document.length == 0) {
      return const ReadingAnchor(
        chapterId: 'root',
        paragraphIndex: 0,
        charOffset: 0,
      );
    }
    return document.buildAnchorForOffset(offset);
  }

  int? offsetFromAnchor({
    required ReaderTextDocument? document,
    required ReadingAnchor? anchor,
  }) {
    if (document == null || document.length == 0) {
      return null;
    }
    return document.offsetFromAnchor(anchor);
  }

  int? resolveStoredOffset({
    required ReaderTextDocument? document,
    required ReadingProgress? progress,
    void Function(String source, int resolvedOffset)? onResolved,
  }) {
    return _progressService.resolveOffset(
      document: document,
      progress: progress,
      onResolved: onResolved,
    );
  }

  int? resolveDoublePageStartOffset({
    required ReaderTextDocument? document,
    required ReadingProgress? progress,
  }) {
    return _progressService.resolveDoublePageStartOffset(
      document: document,
      progress: progress,
    );
  }

  ReadingProgress buildProgress({
    required String bookId,
    required ReaderTextDocument? document,
    required int contentOffset,
    required DateTime updatedAt,
    int? doublePageStartOffset,
    double? scrollOffsetPx,
    double? scrollMaxExtentPx,
  }) {
    return _progressService.buildProgress(
      bookId: bookId,
      document: document,
      contentOffset: contentOffset,
      updatedAt: updatedAt,
      doublePageStartOffset: doublePageStartOffset,
      scrollOffsetPx: scrollOffsetPx,
      scrollMaxExtentPx: scrollMaxExtentPx,
    );
  }

  ReadingLocator locatorForOffset({
    required ReaderTextDocument? document,
    required int contentOffset,
  }) {
    final safeLength = document?.length ?? 0;
    final safeOffset = contentOffset.clamp(0, safeLength);
    final anchor = buildAnchorForOffset(document: document, offset: safeOffset);
    final progression = safeLength <= 0
        ? 0.0
        : (safeOffset / safeLength).clamp(0.0, 1.0);
    return ReadingLocator.fromAnchor(
      anchor: anchor,
      globalOffset: safeOffset,
      progression: progression,
    );
  }

  int? offsetFromLocator({
    required ReaderTextDocument? document,
    required ReadingLocator? locator,
  }) {
    if (document == null || locator == null || document.length == 0) {
      return null;
    }
    final fromAnchor = document.offsetFromAnchor(locator.toAnchor());
    if (fromAnchor != null) {
      return fromAnchor.clamp(0, document.length);
    }
    return locator.globalOffset.clamp(0, document.length);
  }

  List<ReaderSearchResult> search({
    required ReaderTextDocument document,
    required String query,
    int limit = 1000,
    int excerptRadius = 36,
  }) {
    return _searchService.search(
      document: document,
      query: query,
      limit: limit,
      excerptRadius: excerptRadius,
    );
  }

  List<String> normalizeSearchHistory(
    List<String> candidates, {
    int maxItems = 12,
  }) {
    return _searchService.normalizeHistory(candidates, maxItems: maxItems);
  }
}
