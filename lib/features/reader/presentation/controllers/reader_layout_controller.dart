import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_visuals.dart';

enum ReaderTapAction { previous, next, toggleControls }

class ReaderLayoutController {
  const ReaderLayoutController({required this.settings});

  final ReaderSettings settings;

  bool isDoublePageMode(Size viewport) {
    switch (settings.pageLayoutMode) {
      case ReaderPageLayoutMode.single:
        return false;
      case ReaderPageLayoutMode.double:
        return true;
      case ReaderPageLayoutMode.auto:
        return viewport.width >= 820;
    }
  }

  int spreadStepFor(Size viewport) => isDoublePageMode(viewport) ? 2 : 1;

  int clampPageIndex(int target, {required int totalPages, required int step}) {
    if (totalPages <= 1) {
      return 0;
    }
    if (step == 1) {
      return target.clamp(0, totalPages - 1);
    }
    final lastSpreadStart = ((totalPages - 1) ~/ 2) * 2;
    final snapped = (target ~/ 2) * 2;
    return snapped.clamp(0, lastSpreadStart);
  }

  Size textAreaForPagination(Size viewport) {
    final double textHeight = math.max(
      120,
      viewport.height - (readerVerticalPadding * 2),
    );
    final bool isDouble = isDoublePageMode(viewport);
    final double paneWidth = isDouble
        ? math.max(120, (viewport.width - readerDoublePageGap) / 2)
        : viewport.width;
    final double textWidth = math.max(
      80,
      paneWidth - (settings.horizontalPadding * 2),
    );
    return Size(textWidth, textHeight);
  }

  String paginationSignature(Size viewport) {
    final area = textAreaForPagination(viewport);
    final mode = isDoublePageMode(viewport) ? 'double' : 'single';
    return [
      mode,
      area.width.toStringAsFixed(1),
      area.height.toStringAsFixed(1),
      settings.fontFamily,
      settings.fontSize.toStringAsFixed(1),
      settings.lineHeight.toStringAsFixed(2),
      settings.horizontalPadding.toStringAsFixed(1),
    ].join('|');
  }

  ReaderTapAction resolveTapAction({
    required double dx,
    required double width,
    double leftRatio = 0.28,
    double rightRatio = 0.72,
  }) {
    if (width <= 0) {
      return ReaderTapAction.toggleControls;
    }
    final leftEdge = width * leftRatio;
    final rightEdge = width * rightRatio;
    if (dx <= leftEdge) {
      return ReaderTapAction.previous;
    }
    if (dx >= rightEdge) {
      return ReaderTapAction.next;
    }
    return ReaderTapAction.toggleControls;
  }
}
