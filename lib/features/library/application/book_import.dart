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
  });
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
  final addedIds = <String>[];
  var existing = 0;
  var skipped = 0;
  final failed = <String>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    try {
      final path = file.path;
      final book = path == null || path.isEmpty
          ? null
          : await (importFile ?? repository.importBookFile)(path);
      if (book == null) {
        failed.add(file.name);
      } else if (knownIds.add(book.id)) {
        added++;
        addedIds.add(book.id);
      } else {
        existing++;
      }
    } on BookImportSkipped {
      skipped++;
    } catch (_) {
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
  );
}
