import 'dart:convert';

class ReadingAnchor {
  const ReadingAnchor({
    required this.chapterId,
    required this.paragraphIndex,
    required this.charOffset,
  });

  final String chapterId;
  final int paragraphIndex;
  final int charOffset;

  Map<String, Object> toJson() {
    return {
      'chapterId': chapterId,
      'paragraphIndex': paragraphIndex,
      'charOffset': charOffset,
    };
  }

  static ReadingAnchor? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.map((key, value) => MapEntry('$key', value));
    final chapterId = map['chapterId'];
    final paragraphIndex = map['paragraphIndex'];
    final charOffset = map['charOffset'];
    if (chapterId is! String || paragraphIndex is! num || charOffset is! num) {
      return null;
    }
    return ReadingAnchor(
      chapterId: chapterId,
      paragraphIndex: paragraphIndex.toInt().clamp(0, 1 << 30),
      charOffset: charOffset.toInt().clamp(0, 1 << 30),
    );
  }
}

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.positionRatio,
    required this.contentOffset,
    this.pageIndex = 0,
    this.totalPages = 0,
    required this.updatedAt,
    this.scrollOffsetPx,
    this.scrollMaxExtentPx,
    this.anchor,
  });

  final String bookId;
  final double positionRatio;
  final int contentOffset;
  // Legacy fields kept for backward compatibility only.
  final int pageIndex;
  final int totalPages;
  final DateTime updatedAt;
  final double? scrollOffsetPx;
  final double? scrollMaxExtentPx;
  final ReadingAnchor? anchor;

  String toRaw() {
    return jsonEncode({
      'bookId': bookId,
      'positionRatio': positionRatio,
      'contentOffset': contentOffset,
      'pageIndex': pageIndex,
      'totalPages': totalPages,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      if (scrollOffsetPx != null) 'scrollOffsetPx': scrollOffsetPx,
      if (scrollMaxExtentPx != null) 'scrollMaxExtentPx': scrollMaxExtentPx,
      if (anchor != null) 'anchor': anchor!.toJson(),
    });
  }

  static ReadingProgress? fromRaw(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final bookId = json['bookId'];
      final ratio = json['positionRatio'];
      final contentOffset = json['contentOffset'];
      final pageIndex = json['pageIndex'];
      final totalPages = json['totalPages'];
      final updatedAt = json['updatedAt'];
      final scrollOffsetPx = json['scrollOffsetPx'];
      final scrollMaxExtentPx = json['scrollMaxExtentPx'];
      final anchor = ReadingAnchor.fromJson(json['anchor']);
      if (bookId is! String || ratio is! num || updatedAt is! int) {
        return null;
      }
      final safeRatio = ratio.toDouble().clamp(0.0, 1.0);
      final safeContentOffset = contentOffset is int ? contentOffset : 0;
      final safeTotalPages = totalPages is int ? totalPages : 0;
      final safePageIndex = pageIndex is int ? pageIndex : 0;
      return ReadingProgress(
        bookId: bookId,
        positionRatio: safeRatio,
        contentOffset: safeContentOffset < 0 ? 0 : safeContentOffset,
        pageIndex: safePageIndex,
        totalPages: safeTotalPages,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
        scrollOffsetPx: scrollOffsetPx is num
            ? scrollOffsetPx.toDouble().clamp(0.0, double.infinity)
            : null,
        scrollMaxExtentPx: scrollMaxExtentPx is num
            ? scrollMaxExtentPx.toDouble().clamp(0.0, double.infinity)
            : null,
        anchor: anchor,
      );
    } catch (_) {
      return null;
    }
  }
}
