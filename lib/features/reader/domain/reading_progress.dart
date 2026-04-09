import 'dart:convert';

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.positionRatio,
    required this.pageIndex,
    required this.totalPages,
    required this.updatedAt,
  });

  final String bookId;
  final double positionRatio;
  final int pageIndex;
  final int totalPages;
  final DateTime updatedAt;

  String toRaw() {
    return jsonEncode({
      'bookId': bookId,
      'positionRatio': positionRatio,
      'pageIndex': pageIndex,
      'totalPages': totalPages,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
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
      final pageIndex = json['pageIndex'];
      final totalPages = json['totalPages'];
      final updatedAt = json['updatedAt'];
      if (bookId is! String || ratio is! num || updatedAt is! int) {
        return null;
      }
      final safeRatio = ratio.toDouble().clamp(0.0, 1.0);
      final safeTotalPages = totalPages is int ? totalPages : 0;
      final safePageIndex = pageIndex is int ? pageIndex : 0;
      return ReadingProgress(
        bookId: bookId,
        positionRatio: safeRatio,
        pageIndex: safePageIndex,
        totalPages: safeTotalPages,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      );
    } catch (_) {
      return null;
    }
  }
}
