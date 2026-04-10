class ReaderBookmarkController {
  const ReaderBookmarkController._();

  static bool hasNearbyBookmark(
    Set<int> bookmarks, {
    required int anchor,
    int tolerance = 120,
  }) {
    return bookmarks.any((value) => (value - anchor).abs() <= tolerance);
  }

  static Set<int> toggleNearbyBookmark(
    Set<int> bookmarks, {
    required int anchor,
    int tolerance = 120,
  }) {
    final updated = Set<int>.from(bookmarks);
    final hasNearby = hasNearbyBookmark(
      updated,
      anchor: anchor,
      tolerance: tolerance,
    );
    if (hasNearby) {
      updated.removeWhere((value) => (value - anchor).abs() <= tolerance);
    } else {
      updated.add(anchor);
    }
    return updated;
  }
}
