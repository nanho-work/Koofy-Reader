import 'package:flutter/painting.dart';
import 'package:koofy_reader/features/reader/application/state/reader_location_state.dart';
import 'package:koofy_reader/features/reader/core/services/reader_projection_service.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';

class ReaderLocationController {
  const ReaderLocationController({
    this.projectionService = const ReaderProjectionService(),
  });

  final ReaderProjectionService projectionService;

  ReaderLocationState build({
    required String content,
    required bool isDoubleActive,
    required TextPainter? singlePainter,
    required bool hasSingleScrollClients,
    required double singleScrollOffset,
    required double singleMaxScrollExtent,
    required double singleViewportHeight,
    required PaginatedText? spreadPages,
    required int spreadIndex,
    required bool isSpreadJumping,
    required bool hasSpreadClients,
    required double spreadViewportExtent,
    required double spreadScrollOffset,
    required int lastKnownContentOffset,
    required int? pendingAnchorOffset,
    required int? restoredContentOffset,
    required int? restoredDoublePageStartOffset,
    required int? pinnedDoubleContentOffset,
  }) {
    final singleContentOffset = projectionService.currentSingleContentOffset(
      content: content,
      painter: singlePainter,
      hasScrollClients: hasSingleScrollClients,
      scrollOffset: singleScrollOffset,
      maxScrollExtent: singleMaxScrollExtent,
      fallbackOffset: lastKnownContentOffset,
      singleViewportHeight: singleViewportHeight,
    );
    final singleFocusOffset = projectionService.currentSingleContentOffset(
      content: content,
      painter: singlePainter,
      hasScrollClients: hasSingleScrollClients,
      scrollOffset: singleScrollOffset,
      maxScrollExtent: singleMaxScrollExtent,
      fallbackOffset: lastKnownContentOffset,
      viewportBias: 0.42,
      singleViewportHeight: singleViewportHeight,
    );
    final spreadStartIndex = projectionService.currentSpreadStartIndex(
      pages: spreadPages,
      isSpreadJumping: isSpreadJumping,
      spreadIndex: spreadIndex,
      hasSpreadClients: hasSpreadClients,
      spreadViewportExtent: spreadViewportExtent,
      spreadScrollOffset: spreadScrollOffset,
    );
    final contentOffset = projectionService.currentContentOffset(
      content: content,
      isDoubleActive: isDoubleActive,
      spreadPages: spreadPages,
      currentSpreadStartIndex: spreadStartIndex,
      currentSingleContentOffset: singleContentOffset,
      pinnedDoubleContentOffset: pinnedDoubleContentOffset,
    );
    final stableAnchorOffset = projectionService.resolveStableAnchorOffset(
      content: content,
      isDoubleActive: isDoubleActive,
      currentSingleContentOffset: singleContentOffset,
      spreadPages: spreadPages,
      currentSpreadStartIndex: spreadStartIndex,
      pendingAnchorOffset: pendingAnchorOffset,
      restoredContentOffset: restoredContentOffset,
      lastKnownContentOffset: lastKnownContentOffset,
      pinnedDoubleContentOffset: pinnedDoubleContentOffset,
    );
    final doublePageStartOffset =
        (spreadPages != null && spreadPages.length > 0)
        ? spreadPages
              .ranges[spreadStartIndex.clamp(0, spreadPages.length - 1)]
              .start
              .clamp(0, content.length)
        : restoredDoublePageStartOffset?.clamp(0, content.length);

    return ReaderLocationState(
      singleContentOffset: singleContentOffset,
      singleFocusOffset: singleFocusOffset,
      spreadStartIndex: spreadStartIndex,
      contentOffset: contentOffset,
      stableAnchorOffset: stableAnchorOffset,
      doublePageStartOffset: doublePageStartOffset,
    );
  }
}
