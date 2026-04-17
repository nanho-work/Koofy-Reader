import 'package:flutter/painting.dart';

class ReaderPositionService {
  const ReaderPositionService._();

  static int normalizeToLineStartOffset({
    required String content,
    required int offset,
  }) {
    if (content.isEmpty) {
      return 0;
    }
    var cursor = offset.clamp(0, content.length);
    if (cursor >= content.length && content.isNotEmpty) {
      cursor = content.length - 1;
    }
    while (cursor > 0 && content.codeUnitAt(cursor - 1) != 0x0A) {
      cursor--;
    }
    return cursor.clamp(0, content.length);
  }

  static int normalizeToVisualLineStartOffset({
    required String content,
    required int offset,
    required TextPainter? painter,
  }) {
    final fallback = normalizeToLineStartOffset(
      content: content,
      offset: offset,
    );
    if (painter == null || content.isEmpty) {
      return fallback;
    }
    var clamped = offset.clamp(0, content.length);
    if (clamped >= content.length && content.isNotEmpty) {
      clamped = content.length - 1;
    }
    final line = painter.getLineBoundary(TextPosition(offset: clamped));
    return line.start.clamp(0, content.length);
  }

  static int normalizeRestoreOffset({
    required String content,
    required int offset,
    required bool doubleMode,
    TextPainter? singlePainter,
  }) {
    if (doubleMode) {
      return content.isEmpty ? 0 : offset.clamp(0, content.length);
    }
    return normalizeToVisualLineStartOffset(
      content: content,
      offset: offset,
      painter: singlePainter,
    );
  }
}
