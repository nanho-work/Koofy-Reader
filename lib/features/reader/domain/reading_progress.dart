import 'dart:convert';

class ReadingProgress {
  const ReadingProgress({
    required this.bookId,
    required this.positionRatio,
    required this.updatedAt,
  });

  final String bookId;
  final double positionRatio;
  final DateTime updatedAt;

  String toRaw() {
    return jsonEncode({
      'bookId': bookId,
      'positionRatio': positionRatio,
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
      final updatedAt = json['updatedAt'];
      if (bookId is! String || ratio is! num || updatedAt is! int) {
        return null;
      }
      return ReadingProgress(
        bookId: bookId,
        positionRatio: ratio.toDouble().clamp(0.0, 1.0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
      );
    } catch (_) {
      return null;
    }
  }
}
