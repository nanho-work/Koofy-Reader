import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class TextPageRange {
  const TextPageRange({required this.start, required this.end});

  final int start;
  final int end;
}

class PaginatedText {
  const PaginatedText({required this.source, required this.ranges});

  final String source;
  final List<TextPageRange> ranges;

  int get length => ranges.length;

  List<int> toBreakOffsets() {
    return ranges.map((range) => range.end).toList(growable: false);
  }

  String operator [](int index) {
    final range = ranges[index];
    if (range.end <= range.start) {
      return '';
    }
    return source.substring(range.start, range.end);
  }

  static PaginatedText fromBreakOffsets({
    required String source,
    required List<int> offsets,
  }) {
    if (source.isEmpty) {
      return const PaginatedText(
        source: '',
        ranges: [TextPageRange(start: 0, end: 0)],
      );
    }

    final ranges = <TextPageRange>[];
    int start = 0;
    for (final rawEnd in offsets) {
      final end = rawEnd.clamp(start, source.length);
      if (end <= start) {
        continue;
      }
      ranges.add(TextPageRange(start: start, end: end));
      start = end;
      while (start < source.length) {
        final ch = source.codeUnitAt(start);
        if (ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D) {
          start++;
        } else {
          break;
        }
      }
    }

    if (start < source.length) {
      ranges.add(TextPageRange(start: start, end: source.length));
    }
    if (ranges.isEmpty) {
      ranges.add(TextPageRange(start: 0, end: source.length));
    }

    return PaginatedText(source: source, ranges: ranges);
  }
}

class TextPaginationEngine {
  Future<PaginatedText> paginateAsync({
    required String content,
    required double maxWidth,
    required double maxHeight,
    required TextStyle style,
    int yieldEvery = 20,
    int? maxPages,
  }) async {
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) {
      return const PaginatedText(
        source: '',
        ranges: [TextPageRange(start: 0, end: 0)],
      );
    }

    final safeWidth = maxWidth.clamp(80.0, 5000.0);
    final safeHeight = maxHeight.clamp(80.0, 6000.0);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    final estimatedChars = _estimateMaxCharsPerPage(
      maxWidth: safeWidth,
      maxHeight: safeHeight,
      style: style,
    );
    final maxCharsToTry = _maxCharsWindowFor(
      contentLength: normalized.length,
      estimatedChars: estimatedChars,
    );

    final ranges = <TextPageRange>[];
    int start = 0;
    int pageCount = 0;

    while (start < normalized.length) {
      if (maxPages != null && ranges.length >= maxPages) {
        break;
      }
      final end = _findPageEnd(
        normalized,
        start: start,
        maxWidth: safeWidth,
        maxHeight: safeHeight,
        style: style,
        painter: painter,
        maxCharsToTry: maxCharsToTry,
      );
      if (end <= start) {
        final forcedEnd = (start + 1).clamp(0, normalized.length);
        ranges.add(TextPageRange(start: start, end: forcedEnd));
        start = forcedEnd;
      } else {
        final trimmedEnd = _trimRightBoundary(normalized, start, end);
        final safeEnd = trimmedEnd <= start ? end : trimmedEnd;
        ranges.add(TextPageRange(start: start, end: safeEnd));
        start = _consumeLeadingSpaces(normalized, end);
      }

      pageCount++;
      if (pageCount % yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (ranges.isEmpty) {
      return const PaginatedText(
        source: '',
        ranges: [TextPageRange(start: 0, end: 0)],
      );
    }
    return PaginatedText(source: normalized, ranges: ranges);
  }

  int _findPageEnd(
    String source, {
    required int start,
    required double maxWidth,
    required double maxHeight,
    required TextStyle style,
    required TextPainter painter,
    required int maxCharsToTry,
  }) {
    final probeEnd = math.min(source.length, start + maxCharsToTry);
    if (probeEnd <= start) {
      return math.min(source.length, start + 1);
    }
    final probe = source.substring(start, probeEnd);

    painter.text = TextSpan(text: probe, style: style);
    painter.layout(maxWidth: maxWidth);

    if (painter.height <= maxHeight + 0.01) {
      return _adjustBreakByWordBoundary(source, start: start, end: probeEnd);
    }

    // Prefer an exact line boundary that fully fits inside maxHeight.
    double? targetY;
    final lines = painter.computeLineMetrics();
    if (lines.isNotEmpty) {
      final safeBottom = math.max(0.0, maxHeight - 0.5);
      for (final line in lines) {
        final lineBottom = line.baseline + line.descent;
        if (lineBottom <= safeBottom) {
          final lineTop = line.baseline - line.ascent;
          targetY = ((lineTop + lineBottom) * 0.5).clamp(0.0, safeBottom);
        } else {
          break;
        }
      }
    }

    // Fallback for extremely tight heights where no full line fits.
    targetY ??= math.max(0.0, maxHeight * 0.35);
    final dx = math.max(0.0, maxWidth - 1);
    final localEnd = painter
        .getPositionForOffset(Offset(dx, targetY))
        .offset
        .clamp(1, probe.length)
        .toInt();

    final end = (start + localEnd).clamp(start + 1, probeEnd);
    return _adjustBreakByWordBoundary(source, start: start, end: end);
  }

  int _adjustBreakByWordBoundary(
    String source, {
    required int start,
    required int end,
  }) {
    if (end <= start + 1) {
      return end;
    }
    final span = end - start;
    final minLength = (span * 0.6).floor();
    final windowStart = (end - 140).clamp(start + 1, end);
    for (int i = end - 1; i >= windowStart; i--) {
      final ch = source.codeUnitAt(i);
      final isBreak = ch == 0x20 || ch == 0x0A || ch == 0x09;
      if (isBreak && (i - start) >= minLength) {
        return i + 1;
      }
    }
    return end;
  }

  int _consumeLeadingSpaces(String source, int from) {
    int cursor = from;
    while (cursor < source.length) {
      final ch = source.codeUnitAt(cursor);
      if (ch == 0x20 || ch == 0x09) {
        cursor++;
      } else {
        break;
      }
    }
    return cursor;
  }

  int _trimRightBoundary(String source, int start, int end) {
    int cursor = end;
    while (cursor > start) {
      final ch = source.codeUnitAt(cursor - 1);
      if (ch == 0x20 || ch == 0x09 || ch == 0x0A) {
        cursor--;
      } else {
        break;
      }
    }
    return cursor;
  }

  int _estimateMaxCharsPerPage({
    required double maxWidth,
    required double maxHeight,
    required TextStyle style,
  }) {
    final fontSize = (style.fontSize ?? 16).clamp(10.0, 48.0).toDouble();
    final heightFactor = (style.height ?? 1.5).clamp(1.0, 3.0).toDouble();
    final linePixels = (fontSize * heightFactor).clamp(10.0, 120.0);
    final avgCharWidth = (fontSize * 0.56).clamp(5.0, 32.0);

    final lines = (maxHeight / linePixels).clamp(4.0, 260.0).floor();
    final charsPerLine = (maxWidth / avgCharWidth).clamp(10.0, 260.0).floor();

    final estimate = (lines * charsPerLine * 6).clamp(500, 50000);
    return estimate.toInt();
  }

  int _maxCharsWindowFor({
    required int contentLength,
    required int estimatedChars,
  }) {
    final softCap = contentLength > 180000 ? 6500 : 12000;
    return estimatedChars.clamp(1200, softCap).toInt();
  }
}
