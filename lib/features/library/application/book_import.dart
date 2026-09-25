import 'package:koofy_reader/features/library/data/book_repository.dart';

class BookImportFile {
  const BookImportFile(this.name, this.path);
  final String name;
  final String? path;
}

class BookImportResult {
  const BookImportResult(this.added, this.existing, this.failedNames);
  final int added;
  final int existing;
  final List<String> failedNames;
}

/// Import serially: the repository replaces the library index on each write.
/// One unreadable file must not abort the rest of a selection.
Future<BookImportResult> importBooks(
  BookRepository repository,
  List<BookImportFile> files, {
  void Function(int completed, int total)? onProgress,
}) async {
  final knownIds = (await repository.getBooks()).map((b) => b.id).toSet();
  var added = 0;
  var existing = 0;
  final failed = <String>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    try {
      final path = file.path;
      final book = path == null || path.isEmpty
          ? null
          : await repository.importBookFile(path);
      if (book == null) {
        failed.add(file.name);
      } else if (knownIds.add(book.id)) {
        added++;
      } else {
        existing++;
      }
    } catch (_) {
      failed.add(file.name);
    }
    onProgress?.call(index + 1, files.length);
  }
  return BookImportResult(added, existing, failed);
}
