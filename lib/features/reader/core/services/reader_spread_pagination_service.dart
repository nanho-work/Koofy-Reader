import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/core/services/reader_projection_service.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_layout_controller.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_spread_window_controller.dart';

class ReaderSpreadPaginationResult {
  const ReaderSpreadPaginationResult({
    required this.pages,
    required this.mappedIndex,
    required this.signature,
    required this.requestedAnchor,
    required this.windowStartOffset,
    required this.windowEndOffset,
    required this.fromCache,
    required this.usedFallbackWindow,
    this.durationMs,
  });

  final PaginatedText pages;
  final int mappedIndex;
  final String signature;
  final int requestedAnchor;
  final int windowStartOffset;
  final int windowEndOffset;
  final bool fromCache;
  final bool usedFallbackWindow;
  final int? durationMs;
}

class ReaderSpreadPaginationService {
  ReaderSpreadPaginationService({
    TextPaginationEngine? engine,
    ReaderProjectionService? projectionService,
  }) : _engine = engine ?? TextPaginationEngine(),
       _projectionService =
           projectionService ?? const ReaderProjectionService();

  final TextPaginationEngine _engine;
  final ReaderProjectionService _projectionService;
  final Map<String, PaginatedText> _cache = <String, PaginatedText>{};

  Future<ReaderSpreadPaginationResult> paginate({
    required ReaderTextDocument document,
    required ReaderLayoutController layout,
    required Size viewport,
    required MediaQueryData mediaQueryData,
    required TextStyle style,
    required int anchorOffset,
  }) async {
    final requestedAnchor = anchorOffset.clamp(0, document.length);
    final baseSignature = layout.paginationSignature(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    final primaryWindow = ReaderSpreadWindowController.buildWindow(
      content: document.content,
      paragraphRanges: document.paragraphRanges,
      anchorOffset: requestedAnchor,
    );
    final primaryResult = await _paginateWindow(
      document: document,
      layout: layout,
      viewport: viewport,
      mediaQueryData: mediaQueryData,
      style: style,
      requestedAnchor: requestedAnchor,
      baseSignature: baseSignature,
      window: primaryWindow,
      usedFallbackWindow: false,
    );
    if (_spreadContainsAnchor(primaryResult, requestedAnchor)) {
      return primaryResult;
    }

    final fallbackStartOffset =
        (requestedAnchor -
                (ReaderSpreadWindowController.doubleWindowMinChars ~/ 2))
            .clamp(0, document.length);
    final fallbackWindow = ReaderSpreadWindowController.buildWindow(
      content: document.content,
      paragraphRanges: document.paragraphRanges,
      anchorOffset: requestedAnchor,
      forceStartOffset: fallbackStartOffset,
    );
    if (fallbackWindow.startOffset == primaryWindow.startOffset &&
        fallbackWindow.endOffset == primaryWindow.endOffset) {
      return primaryResult;
    }

    final fallbackResult = await _paginateWindow(
      document: document,
      layout: layout,
      viewport: viewport,
      mediaQueryData: mediaQueryData,
      style: style,
      requestedAnchor: requestedAnchor,
      baseSignature: baseSignature,
      window: fallbackWindow,
      usedFallbackWindow: true,
    );
    if (_spreadContainsAnchor(fallbackResult, requestedAnchor)) {
      return fallbackResult;
    }
    return primaryResult;
  }

  Future<ReaderSpreadPaginationResult> _paginateWindow({
    required ReaderTextDocument document,
    required ReaderLayoutController layout,
    required Size viewport,
    required MediaQueryData mediaQueryData,
    required TextStyle style,
    required int requestedAnchor,
    required String baseSignature,
    required ReaderPaginationWindow window,
    required bool usedFallbackWindow,
  }) async {
    final signature =
        '$baseSignature|${window.startOffset}|${window.endOffset}';
    final cached = _cache[signature];
    if (cached != null) {
      return ReaderSpreadPaginationResult(
        pages: cached,
        mappedIndex: _mapSpreadIndexByOffset(cached, requestedAnchor),
        signature: signature,
        requestedAnchor: requestedAnchor,
        windowStartOffset: window.startOffset,
        windowEndOffset: window.endOffset,
        fromCache: true,
        usedFallbackWindow: usedFallbackWindow,
      );
    }

    final textArea = layout.textAreaForPagination(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    final startedAt = DateTime.now();
    final localPages = await _engine.paginateAsync(
      content: window.content,
      maxWidth: textArea.width,
      maxHeight: textArea.height,
      style: style,
      yieldEvery: 12,
    );
    final globalPages = ReaderSpreadWindowController.toGlobalPaginatedText(
      localPages: localPages,
      windowStartOffset: window.startOffset,
      sourceContent: document.content,
    );
    _cache[signature] = globalPages;
    if (_cache.length > 6) {
      _cache.remove(_cache.keys.first);
    }

    return ReaderSpreadPaginationResult(
      pages: globalPages,
      mappedIndex: _mapSpreadIndexByOffset(globalPages, requestedAnchor),
      signature: signature,
      requestedAnchor: requestedAnchor,
      windowStartOffset: window.startOffset,
      windowEndOffset: window.endOffset,
      fromCache: false,
      usedFallbackWindow: usedFallbackWindow,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
  }

  bool _spreadContainsAnchor(
    ReaderSpreadPaginationResult result,
    int requestedAnchor,
  ) {
    final pages = result.pages;
    if (pages.length == 0 || pages.ranges.isEmpty) {
      return false;
    }
    final safeIndex = result.mappedIndex.clamp(0, pages.length - 1);
    final left = pages.ranges[safeIndex];
    final right = pages.ranges[(safeIndex + 1).clamp(0, pages.length - 1)];
    if (requestedAnchor >= pages.source.length) {
      return right.end >= pages.source.length;
    }
    return requestedAnchor >= left.start && requestedAnchor < right.end;
  }

  int _mapSpreadIndexByOffset(PaginatedText pages, int offset) {
    return _projectionService.mapSpreadIndexByOffset(
      pages,
      offset.clamp(0, pages.source.length),
    );
  }
}
