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

class ReadingLocator {
  const ReadingLocator({
    required this.chapterId,
    required this.paragraphIndex,
    required this.charOffset,
    required this.globalOffset,
    required this.progression,
  });

  factory ReadingLocator.fromAnchor({
    required ReadingAnchor anchor,
    required int globalOffset,
    required double progression,
  }) {
    return ReadingLocator(
      chapterId: anchor.chapterId,
      paragraphIndex: anchor.paragraphIndex,
      charOffset: anchor.charOffset,
      globalOffset: globalOffset.clamp(0, 1 << 30),
      progression: progression.clamp(0.0, 1.0),
    );
  }

  final String chapterId;
  final int paragraphIndex;
  final int charOffset;
  final int globalOffset;
  final double progression;

  ReadingAnchor toAnchor() {
    return ReadingAnchor(
      chapterId: chapterId,
      paragraphIndex: paragraphIndex,
      charOffset: charOffset,
    );
  }

  Map<String, Object> toJson() {
    return {
      'chapterId': chapterId,
      'paragraphIndex': paragraphIndex,
      'charOffset': charOffset,
      'globalOffset': globalOffset,
      'progression': progression,
    };
  }

  static ReadingLocator? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final map = raw.map((key, value) => MapEntry('$key', value));
    final chapterId = map['chapterId'];
    final paragraphIndex = map['paragraphIndex'];
    final charOffset = map['charOffset'];
    final globalOffset = map['globalOffset'];
    final progression = map['progression'];
    if (chapterId is! String ||
        paragraphIndex is! num ||
        charOffset is! num ||
        globalOffset is! num ||
        progression is! num) {
      return null;
    }
    return ReadingLocator(
      chapterId: chapterId,
      paragraphIndex: paragraphIndex.toInt().clamp(0, 1 << 30),
      charOffset: charOffset.toInt().clamp(0, 1 << 30),
      globalOffset: globalOffset.toInt().clamp(0, 1 << 30),
      progression: progression.toDouble().clamp(0.0, 1.0),
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
    this.locator,
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
  final ReadingLocator? locator;

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
      if (locator != null) 'locator': locator!.toJson(),
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
      final locator = ReadingLocator.fromJson(json['locator']);
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
        locator: locator,
      );
    } catch (_) {
      return null;
    }
  }
}
