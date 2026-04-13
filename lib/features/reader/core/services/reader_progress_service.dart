import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

class ReaderProgressService {
  const ReaderProgressService();

  int? resolveOffset({
    required ReaderTextDocument? document,
    required ReadingProgress? progress,
    void Function(String source, int resolvedOffset)? onResolved,
  }) {
    if (progress == null || document == null || document.length == 0) {
      return null;
    }

    if (progress.locator != null) {
      final resolved = progress.locator!.globalOffset.clamp(0, document.length);
      onResolved?.call('locatorOffset', resolved);
      return resolved;
    }

    final locatorAnchor = progress.locator?.toAnchor();
    final fromLocatorAnchor = document.offsetFromAnchor(locatorAnchor);
    if (fromLocatorAnchor != null) {
      final resolved = fromLocatorAnchor.clamp(0, document.length);
      onResolved?.call('locator', resolved);
      return resolved;
    }

    final fromAnchor = document.offsetFromAnchor(progress.anchor);
    if (fromAnchor != null) {
      final resolved = fromAnchor.clamp(0, document.length);
      onResolved?.call('anchor', resolved);
      return resolved;
    }

    if (progress.contentOffset > 0) {
      final resolved = progress.contentOffset.clamp(0, document.length);
      onResolved?.call('contentOffset', resolved);
      return resolved;
    }

    final resolved = (progress.positionRatio.clamp(0.0, 1.0) * document.length)
        .round()
        .clamp(0, document.length);
    onResolved?.call('ratio', resolved);
    return resolved;
  }

  ReadingProgress buildProgress({
    required String bookId,
    required ReaderTextDocument? document,
    required int contentOffset,
    required DateTime updatedAt,
    double? scrollOffsetPx,
    double? scrollMaxExtentPx,
  }) {
    final safeDocumentLength = document?.length ?? 0;
    final safeOffset = contentOffset.clamp(0, safeDocumentLength);
    final ratio = safeDocumentLength <= 0
        ? 0.0
        : (safeOffset / safeDocumentLength).clamp(0.0, 1.0);
    final anchor = (document == null || safeDocumentLength == 0)
        ? const ReadingAnchor(
            chapterId: 'root',
            paragraphIndex: 0,
            charOffset: 0,
          )
        : document.buildAnchorForOffset(safeOffset);
    final locator = ReadingLocator.fromAnchor(
      anchor: anchor,
      globalOffset: safeOffset,
      progression: ratio,
    );

    return ReadingProgress(
      bookId: bookId,
      positionRatio: ratio,
      contentOffset: safeOffset,
      updatedAt: updatedAt,
      scrollOffsetPx: scrollOffsetPx,
      scrollMaxExtentPx: scrollMaxExtentPx,
      anchor: anchor,
      locator: locator,
    );
  }
}
