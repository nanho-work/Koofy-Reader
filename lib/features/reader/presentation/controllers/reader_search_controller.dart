class ReaderSearchController {
  const ReaderSearchController._();

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

  static List<int> findQueryOffsets({
    required String source,
    required String query,
    int limit = 1000,
  }) {
    if (source.isEmpty) {
      return const <int>[];
    }

    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <int>[];
    }

    final haystack = source.toLowerCase();
    final offsets = <int>[];
    int cursor = 0;
    while (cursor < haystack.length) {
      final found = haystack.indexOf(needle, cursor);
      if (found < 0) {
        break;
      }
      offsets.add(found);
      if (offsets.length >= limit) {
        break;
      }
      cursor = found + needle.length;
    }
    return offsets;
  }
}
