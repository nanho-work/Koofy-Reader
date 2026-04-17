import 'package:koofy_reader/features/reader/core/models/reader_search_result.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

class ReaderSearchService {
  const ReaderSearchService();

  List<ReaderSearchResult> search({
    required ReaderTextDocument document,
    required String query,
    int limit = 1000,
    int excerptRadius = 36,
  }) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || document.length == 0) {
      return const <ReaderSearchResult>[];
    }

    final offsets = document.searchOffsets(normalizedQuery, limit: limit);
    if (offsets.isEmpty) {
      return const <ReaderSearchResult>[];
    }

    return offsets
        .map((offset) {
          final safeOffset = offset.clamp(0, document.length);
          final anchor = document.buildAnchorForOffset(safeOffset);
          final locator = ReadingLocator.fromAnchor(
            anchor: anchor,
            globalOffset: safeOffset,
            progression: document.length <= 0
                ? 0.0
                : (safeOffset / document.length).clamp(0.0, 1.0),
          );
          return ReaderSearchResult(
            query: normalizedQuery,
            offset: safeOffset,
            anchor: anchor,
            locator: locator,
            excerpt: buildExcerpt(
              source: document.content,
              offset: safeOffset,
              query: normalizedQuery,
              radius: excerptRadius,
            ),
          );
        })
        .toList(growable: false);
  }

  static String buildExcerpt({
    required String source,
    required int offset,
    required String query,
    int radius = 36,
  }) {
    if (source.isEmpty) {
      return '';
    }
    final safeOffset = offset.clamp(0, source.length);
    final safeRadius = radius.clamp(8, 240);
    final start = (safeOffset - safeRadius).clamp(0, source.length);
    final end = (safeOffset + query.length + safeRadius).clamp(
      start,
      source.length,
    );
    final slice = source.substring(start, end).replaceAll(RegExp(r'\s+'), ' ');
    final prefix = start > 0 ? '...' : '';
    final suffix = end < source.length ? '...' : '';
    return '$prefix${slice.trim()}$suffix';
  }

  List<String> normalizeHistory(List<String> candidates, {int maxItems = 12}) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final item in candidates) {
      final trimmed = item.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (!seen.add(key)) continue;
      normalized.add(trimmed);
      if (normalized.length >= maxItems) {
        break;
      }
    }
    return normalized;
  }
}
