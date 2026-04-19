import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/core/services/reader_position_service.dart';

class ReaderProjectionService {
  const ReaderProjectionService();

  int currentSingleContentOffset({
    required String content,
    required TextPainter? painter,
    required bool hasScrollClients,
    required double scrollOffset,
    required double maxScrollExtent,
    required int fallbackOffset,
    double viewportBias = 0.0,
    double singleViewportHeight = 0.0,
  }) {
    if (content.isEmpty) {
      return 0;
    }
    if (!hasScrollClients) {
      return fallbackOffset.clamp(0, content.length);
    }
    if (painter == null) {
      if (maxScrollExtent <= 0) {
        return fallbackOffset.clamp(0, content.length);
      }
      final effectiveScrollOffset = (scrollOffset +
              (singleViewportHeight * viewportBias))
          .clamp(0.0, maxScrollExtent);
      final ratio = (effectiveScrollOffset / maxScrollExtent).clamp(0.0, 1.0);
      return (ratio * content.length).round().clamp(0, content.length);
    }
    final effectiveScrollOffset = maxScrollExtent <= 0
        ? 0.0
        : (scrollOffset + (singleViewportHeight * viewportBias)).clamp(
            0.0,
            maxScrollExtent,
          );
    final scrollRatio = maxScrollExtent <= 0
        ? 0.0
        : (effectiveScrollOffset / maxScrollExtent).clamp(0.0, 1.0);
    final localY = (scrollRatio * painter.height).clamp(0.0, painter.height);
    final position = painter.getPositionForOffset(Offset(0, localY));
    return position.offset.clamp(0, content.length);
  }

  double singleScrollOffsetForContentOffset({
    required String content,
    required TextPainter? painter,
    required int contentOffset,
    required bool preserveRawOffset,
    required bool hasScrollClients,
    required double maxScrollExtent,
    required double singleViewportHeight,
  }) {
    if (content.isEmpty) {
      return 0;
    }
    if (painter == null) {
      if (!hasScrollClients || maxScrollExtent <= 0) {
        return 0;
      }
      final normalizedOffset = preserveRawOffset
          ? contentOffset.clamp(0, content.length)
          : ReaderPositionService.normalizeToLineStartOffset(
              content: content,
              offset: contentOffset,
            );
      final ratio = (normalizedOffset / content.length).clamp(0.0, 1.0);
      return (ratio * maxScrollExtent).clamp(0.0, maxScrollExtent);
    }
    final clampedOffset = preserveRawOffset
        ? contentOffset.clamp(0, content.length)
        : ReaderPositionService.normalizeToVisualLineStartOffset(
            content: content,
            offset: contentOffset,
            painter: painter,
          );
    final caretOffset = painter.getOffsetForCaret(
      TextPosition(offset: clampedOffset),
      Rect.zero,
    );
    final raw = caretOffset.dy.clamp(0.0, double.infinity);

    if (hasScrollClients) {
      if (maxScrollExtent <= 0 || painter.height <= 0) {
        return 0;
      }
      final ratio = (raw / painter.height).clamp(0.0, 1.0);
      return (ratio * maxScrollExtent).clamp(0.0, maxScrollExtent);
    }

    final estimatedExtent = painter.height - singleViewportHeight;
    final estimatedMax = estimatedExtent > 0 ? estimatedExtent : 0.0;
    final ratio = painter.height <= 0
        ? 0.0
        : (raw / painter.height).clamp(0.0, 1.0);
    return (ratio * estimatedMax).clamp(0.0, estimatedMax);
  }

  int currentSpreadStartIndex({
    required PaginatedText? pages,
    required bool isSpreadJumping,
    required int spreadIndex,
    required bool hasSpreadClients,
    required double spreadViewportExtent,
    required double spreadScrollOffset,
  }) {
    if (pages == null || pages.length == 0) {
      return 0;
    }
    if (isSpreadJumping || !hasSpreadClients || spreadViewportExtent <= 0) {
      return spreadIndex.clamp(0, pages.length - 1);
    }
    final rowCount = (pages.length / 2).ceil();
    final expectedRow = (spreadIndex / 2).floor();
    final actualRow = spreadScrollOffset / spreadViewportExtent;
    if ((actualRow - expectedRow).abs() < 0.5) {
      return spreadIndex.clamp(0, pages.length - 1);
    }
    final row = actualRow.round();
    final safeRow = row.clamp(0, rowCount - 1);
    return clampSpreadStartIndex(safeRow * 2, pages.length);
  }

  int currentContentOffset({
    required String content,
    required bool isDoubleActive,
    required PaginatedText? spreadPages,
    required int currentSpreadStartIndex,
    required int currentSingleContentOffset,
    int? pinnedDoubleContentOffset,
  }) {
    if (content.isEmpty) {
      return 0;
    }
    if (isDoubleActive && spreadPages != null && spreadPages.length > 0) {
      if (pinnedDoubleContentOffset != null) {
        final pinned = pinnedDoubleContentOffset.clamp(0, content.length);
        final safeIndex = currentSpreadStartIndex.clamp(
          0,
          spreadPages.length - 1,
        );
        final left = spreadPages.ranges[safeIndex];
        final right = spreadPages
            .ranges[(safeIndex + 1).clamp(0, spreadPages.length - 1)];
        if (pinned >= left.start && pinned < right.end) {
          return pinned;
        }
      }
      final safeIndex = currentSpreadStartIndex.clamp(
        0,
        spreadPages.length - 1,
      );
      return spreadPages.ranges[safeIndex].start.clamp(
        0,
        spreadPages.source.length,
      );
    }
    return currentSingleContentOffset.clamp(0, content.length);
  }

  int resolveStableAnchorOffset({
    required String content,
    required bool isDoubleActive,
    required int currentSingleContentOffset,
    required PaginatedText? spreadPages,
    required int currentSpreadStartIndex,
    required int? pendingAnchorOffset,
    required int? restoredContentOffset,
    required int lastKnownContentOffset,
    int? pinnedDoubleContentOffset,
  }) {
    if (!isDoubleActive) {
      return currentSingleContentOffset.clamp(0, content.length);
    }
    if (pinnedDoubleContentOffset != null) {
      return pinnedDoubleContentOffset.clamp(0, content.length);
    }
    if (spreadPages != null && spreadPages.length > 0) {
      final safeIndex = currentSpreadStartIndex.clamp(
        0,
        spreadPages.length - 1,
      );
      return spreadPages.ranges[safeIndex].start.clamp(
        0,
        spreadPages.source.length,
      );
    }
    if (pendingAnchorOffset != null) {
      return pendingAnchorOffset.clamp(0, content.length);
    }
    if (restoredContentOffset != null) {
      return restoredContentOffset.clamp(0, content.length);
    }
    return lastKnownContentOffset.clamp(0, content.length);
  }

  int mapSpreadIndexByOffset(PaginatedText pages, int offset) {
    if (pages.length <= 1) {
      return 0;
    }
    int low = 0;
    int high = pages.ranges.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      final end = pages.ranges[mid].end;
      if (offset < end) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    final raw = low.clamp(0, pages.ranges.length - 1);
    final aligned = raw.isOdd ? raw - 1 : raw;
    return clampSpreadStartIndex(aligned, pages.length);
  }

  bool containsOffset({
    required PaginatedText pages,
    required int offset,
    required int contentLength,
  }) {
    if (pages.length == 0 || pages.ranges.isEmpty) {
      return false;
    }
    final normalized = offset.clamp(0, contentLength);
    final start = pages.ranges.first.start;
    final end = pages.ranges.last.end;
    if (normalized >= contentLength) {
      return end >= contentLength;
    }
    return normalized >= start && normalized < end;
  }

  int clampSpreadStartIndex(int index, int totalPages) {
    if (totalPages <= 1) {
      return 0;
    }
    final maxRaw = totalPages - 1;
    final maxLeft = maxRaw.isOdd ? maxRaw - 1 : maxRaw;
    final clamped = index.clamp(0, maxLeft);
    return clamped.isOdd ? clamped - 1 : clamped;
  }
}
