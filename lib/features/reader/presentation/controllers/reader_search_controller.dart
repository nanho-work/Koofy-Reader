import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';

class ReaderSearchController {
  const ReaderSearchController({required this.source, required this.ranges});

  final String source;
  final List<TextPageRange> ranges;

  List<int> findQueryPages(String query) {
    if (query.isEmpty || ranges.isEmpty || source.isEmpty) {
      return const <int>[];
    }

    final lowerText = source.toLowerCase();
    final needle = query.toLowerCase();
    final result = <int>[];
    int from = 0;

    while (from < lowerText.length) {
      final index = lowerText.indexOf(needle, from);
      if (index < 0) {
        break;
      }
      final page = _pageForOffset(index);
      if (page >= 0 && (result.isEmpty || result.last != page)) {
        result.add(page);
      }
      from = index + needle.length;
    }

    return result;
  }

  int _pageForOffset(int offset) {
    if (ranges.isEmpty) return -1;
    int low = 0;
    int high = ranges.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final range = ranges[mid];
      if (offset < range.start) {
        high = mid - 1;
      } else if (offset >= range.end) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return ranges.length - 1;
  }

  static List<String> normalizeHistory(
    List<String> candidates, {
    int maxItems = 12,
  }) {
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

  static int moveCursor({
    required int current,
    required int delta,
    required int length,
  }) {
    if (length <= 0) {
      return -1;
    }
    final normalizedCurrent = current < 0 ? 0 : current % length;
    final next = (normalizedCurrent + delta) % length;
    return next < 0 ? next + length : next;
  }
}
