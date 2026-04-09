import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_visuals.dart';

enum ReaderTapAction { previous, next, toggleControls }

class ReaderLayoutController {
  const ReaderLayoutController({required this.settings});

  final ReaderSettings settings;

  bool isDoublePageMode(Size viewport, {MediaQueryData? mediaQueryData}) {
    switch (settings.pageLayoutMode) {
      case ReaderPageLayoutMode.single:
        return false;
      case ReaderPageLayoutMode.double:
        return true;
      case ReaderPageLayoutMode.auto:
        return _autoShouldUseDouble(viewport, mediaQueryData: mediaQueryData);
    }
  }

  int spreadStepFor(Size viewport, {MediaQueryData? mediaQueryData}) {
    return isDoublePageMode(viewport, mediaQueryData: mediaQueryData) ? 2 : 1;
  }

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

  Size textAreaForPagination(Size viewport, {MediaQueryData? mediaQueryData}) {
    final linePixels = (settings.fontSize * settings.lineHeight).clamp(
      12.0,
      120.0,
    );
    // Keep a generous guard zone so no lines are clipped at page bottom.
    final heightGuard = (linePixels * 2.2) + 16;
    final double textHeight = math.max(
      120,
      viewport.height -
          (readerVerticalPadding * 2) -
          readerContentBottomInset -
          heightGuard,
    );
    final bool isDouble = isDoublePageMode(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    final double paneWidth = isDouble
        ? math.max(120, (viewport.width - readerDoublePageGap) / 2)
        : viewport.width;
    final double textWidth = math.max(
      80,
      paneWidth - (settings.horizontalPadding * 2),
    );
    return Size(textWidth, textHeight);
  }

  String paginationSignature(Size viewport, {MediaQueryData? mediaQueryData}) {
    final area = textAreaForPagination(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    final mode = isDoublePageMode(viewport, mediaQueryData: mediaQueryData)
        ? 'double'
        : 'single';
    final hasFoldFeature =
        mediaQueryData?.displayFeatures.any(
          (feature) => _isFoldLikeType(feature.type.toString()),
        ) ??
        false;
    // Quantize dimensions so tiny viewport shifts don't invalidate cache.
    final widthBucket = ((area.width / 24).round() * 24).toDouble();
    final heightBucket = ((area.height / 160).round() * 160).toDouble();
    return [
      mode,
      hasFoldFeature ? 'fold' : 'plain',
      widthBucket.toStringAsFixed(0),
      heightBucket.toStringAsFixed(0),
      settings.fontFamily,
      settings.fontSize.toStringAsFixed(1),
      settings.lineHeight.toStringAsFixed(2),
      settings.horizontalPadding.toStringAsFixed(1),
    ].join('|');
  }

  ReaderTapAction resolveTapAction({
    required double dx,
    required double width,
    double leftRatio = 0.5,
  }) {
    if (width <= 0) {
      return ReaderTapAction.toggleControls;
    }
    final leftEdge = width * leftRatio;
    if (dx <= leftEdge) {
      return ReaderTapAction.previous;
    }
    return ReaderTapAction.next;
  }

  bool _autoShouldUseDouble(Size viewport, {MediaQueryData? mediaQueryData}) {
    final hasFoldFeature =
        mediaQueryData?.displayFeatures.any(
          (feature) => _isFoldLikeType(feature.type.toString()),
        ) ??
        false;
    if (hasFoldFeature) {
      return true;
    }

    final ratio = viewport.height == 0 ? 0.0 : viewport.width / viewport.height;
    if (ratio >= 0.70) {
      return true;
    }
    if (viewport.shortestSide >= 600 || viewport.width >= 520) {
      return true;
    }
    // Foldables in portrait can still report narrow logical widths.
    if (viewport.shortestSide >= 540 && viewport.longestSide >= 840) {
      return true;
    }
    return false;
  }

  bool _isFoldLikeType(String value) {
    final lower = value.toLowerCase();
    return lower.contains('fold') || lower.contains('hinge');
  }
}
