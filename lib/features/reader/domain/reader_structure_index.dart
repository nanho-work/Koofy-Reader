import 'dart:convert';

class ReaderParagraphRangeData {
  const ReaderParagraphRangeData({required this.start, required this.end});

  final int start;
  final int end;

  Map<String, Object> toJson() {
    return {'start': start, 'end': end};
  }

  static ReaderParagraphRangeData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry('$key', value));
    final start = map['start'];
    final end = map['end'];
    if (start is! num || end is! num) {
      return null;
    }
    final safeStart = start.toInt().clamp(0, 1 << 30);
    final safeEnd = end.toInt().clamp(safeStart, 1 << 30);
    return ReaderParagraphRangeData(start: safeStart, end: safeEnd);
  }
}

class ReaderChapterRangeData {
  const ReaderChapterRangeData({
    required this.id,
    required this.paragraphStartIndex,
    required this.paragraphEndIndex,
  });

  final String id;
  final int paragraphStartIndex;
  final int paragraphEndIndex;

  Map<String, Object> toJson() {
    return {
      'id': id,
      'paragraphStartIndex': paragraphStartIndex,
      'paragraphEndIndex': paragraphEndIndex,
    };
  }

  static ReaderChapterRangeData? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry('$key', value));
    final id = map['id'];
    final paragraphStartIndex = map['paragraphStartIndex'];
    final paragraphEndIndex = map['paragraphEndIndex'];
    if (id is! String ||
        paragraphStartIndex is! num ||
        paragraphEndIndex is! num) {
      return null;
    }
    final safeStart = paragraphStartIndex.toInt().clamp(0, 1 << 30);
    final safeEnd = paragraphEndIndex.toInt().clamp(safeStart, 1 << 30);
    return ReaderChapterRangeData(
      id: id,
      paragraphStartIndex: safeStart,
      paragraphEndIndex: safeEnd,
    );
  }
}

class ReaderStructureIndex {
  const ReaderStructureIndex({
    required this.schemaVersion,
    required this.contentLength,
    required this.contentHash,
    required this.paragraphs,
    required this.chapters,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int contentLength;
  final String contentHash;
  final List<ReaderParagraphRangeData> paragraphs;
  final List<ReaderChapterRangeData> chapters;

  String toRaw() {
    return jsonEncode({
      'schemaVersion': schemaVersion,
      'contentLength': contentLength,
      'contentHash': contentHash,
      'paragraphs': paragraphs.map((item) => item.toJson()).toList(),
      'chapters': chapters.map((item) => item.toJson()).toList(),
    });
  }

  static ReaderStructureIndex? fromRaw(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final schemaVersion = decoded['schemaVersion'];
      final contentLength = decoded['contentLength'];
      final contentHash = decoded['contentHash'];
      final paragraphsRaw = decoded['paragraphs'];
      final chaptersRaw = decoded['chapters'];
      if (schemaVersion is! int ||
          contentLength is! int ||
          contentHash is! String ||
          paragraphsRaw is! List ||
          chaptersRaw is! List) {
        return null;
      }

      final paragraphs = paragraphsRaw
          .map(ReaderParagraphRangeData.fromJson)
          .whereType<ReaderParagraphRangeData>()
          .toList();
      final chapters = chaptersRaw
          .map(ReaderChapterRangeData.fromJson)
          .whereType<ReaderChapterRangeData>()
          .toList();
      if (paragraphs.isEmpty) {
        return null;
      }

      return ReaderStructureIndex(
        schemaVersion: schemaVersion,
        contentLength: contentLength,
        contentHash: contentHash,
        paragraphs: paragraphs,
        chapters: chapters,
      );
    } catch (_) {
      return null;
    }
  }
}
