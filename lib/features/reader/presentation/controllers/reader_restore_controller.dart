import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

class ReaderRestoreController {
  const ReaderRestoreController._();

  static int? resolveStoredOffset({
    required ReadingProgress? progress,
    required int contentLength,
    required int? Function(ReadingAnchor? anchor) offsetFromAnchor,
    void Function(String source, int resolvedOffset)? onResolved,
  }) {
    if (progress == null) {
      return null;
    }
    final fromAnchor = offsetFromAnchor(progress.anchor);
    if (fromAnchor != null) {
      final resolved = fromAnchor.clamp(0, contentLength);
      onResolved?.call('anchor', resolved);
      return resolved;
    }
    final fallback = progress.contentOffset.clamp(0, contentLength);
    onResolved?.call('contentOffset', fallback);
    return fallback;
  }

  static ReadingProgress buildProgress({
    required String bookId,
    required double ratio,
    required int contentOffset,
    required ReadingAnchor anchor,
    required DateTime updatedAt,
    double? scrollOffsetPx,
    double? scrollMaxExtentPx,
  }) {
    return ReadingProgress(
      bookId: bookId,
      positionRatio: ratio.clamp(0.0, 1.0),
      contentOffset: contentOffset < 0 ? 0 : contentOffset,
      updatedAt: updatedAt,
      scrollOffsetPx: scrollOffsetPx,
      scrollMaxExtentPx: scrollMaxExtentPx,
      anchor: anchor,
    );
  }
}
