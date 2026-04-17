import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_visuals.dart';

enum ReaderTapAction { previous, next }

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

  Size textAreaForPagination(Size viewport, {MediaQueryData? mediaQueryData}) {
    final linePixels = (settings.fontSize * settings.lineHeight).clamp(
      12.0,
      120.0,
    );
    // Keep pagination height aligned with actual pane height and add
    // only a small safety margin to prevent bottom-line clipping.
    final heightSafety = (linePixels * 0.35) + 4;
    final double textHeight = math.max(
      24,
      viewport.height -
          (readerVerticalPadding * 2) -
          readerContentBottomInset -
          heightSafety,
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
    // Quantize lightly to absorb tiny jitter while still reacting to
    // real viewport changes (fold/IME/system bars).
    final widthBucket = ((area.width / 16).round() * 16).toDouble();
    final heightBucket = ((area.height / 16).round() * 16).toDouble();
    return [
      mode,
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
      return ReaderTapAction.next;
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
