import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

class ReaderSearchResult {
  const ReaderSearchResult({
    required this.query,
    required this.offset,
    required this.anchor,
    required this.locator,
    required this.excerpt,
  });

  final String query;
  final int offset;
  final ReadingAnchor anchor;
  final ReadingLocator locator;
  final String excerpt;
}
