import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';

class BookImportSkipped implements Exception {}

class BookImportFile {
  const BookImportFile(this.name, this.path);
  final String name;
  final String? path;
}

class BookImportResult {
  const BookImportResult(
    this.added,
    this.existing,
    this.failedNames, {
    this.addedIds = const [],
    this.skipped = 0,
    this.importedIds = const [],
  });
  final List<String> importedIds;
  final int added;
  final int skipped;
  final List<String> addedIds;
  final int existing;
  final List<String> failedNames;
}

/// Import serially: the repository replaces the library index on each write.
/// One unreadable file must not abort the rest of a selection.
Future<BookImportResult> importBooks(
  BookRepository repository,
  List<BookImportFile> files, {
  void Function(int completed, int total)? onProgress,
  Future<Book?> Function(String path)? importFile,
}) async {
  final knownIds = (await repository.getBooks()).map((b) => b.id).toSet();
  var added = 0;
  final importedIds = <String>{};
  final addedIds = <String>[];
  var existing = 0;
  var skipped = 0;
  final failed = <String>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    final format = file.name.split('.').last.toLowerCase();
    final analytics = ReaderAnalytics.instance;
    analytics.bookImport(format, 'start');
    try {
      final path = file.path;
      final book = path == null || path.isEmpty
          ? null
          : await (importFile ?? repository.importBookFile)(path);
      if (book == null) {
        analytics.bookImport(format, 'failed');
        failed.add(file.name);
      } else if (knownIds.add(book.id)) {
        analytics.bookImport(format, 'success');
        added++;
        addedIds.add(book.id);
      } else {
        analytics.bookImport(format, 'existing');
        existing++;
      }
      if (book != null) importedIds.add(book.id);
    } on BookImportSkipped {
      analytics.bookImport(format, 'cancelled');
      skipped++;
    } catch (_) {
      analytics.bookImport(format, 'failed');
      failed.add(file.name);
    }
    onProgress?.call(index + 1, files.length);
  }
  return BookImportResult(
    added,
    existing,
    failed,
    addedIds: List.unmodifiable(addedIds),
    skipped: skipped,
    importedIds: List.unmodifiable(importedIds),
  );
}
