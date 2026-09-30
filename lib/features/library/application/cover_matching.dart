import 'package:koofy_reader/core/storage/library_mutations.dart';
import 'package:koofy_reader/features/library/application/book_import.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

const coverImageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
String fileExtension(String name) => name.split('.').last.toLowerCase();
String coverMatchKey(String name) {
  final base = name.split(RegExp(r'[/\\]')).last;
  final dot = base.lastIndexOf('.');
  return (dot > 0 ? base.substring(0, dot) : base).trim().toLowerCase();
}

class CoverMatch {
  const CoverMatch(this.book, this.images);
  final Book book;
  final List<BookImportFile> images;
}

class CoverMatchPlan {
  CoverMatchPlan(List<Book> books, List<BookImportFile> images) {
    final byName = <String, List<BookImportFile>>{};
    for (final image in images) {
      if (!coverImageExtensions.contains(fileExtension(image.name))) continue;
      byName.putIfAbsent(coverMatchKey(image.name), () => []).add(image);
    }
    final counts = <String, int>{};
    for (final book in books) {
      final name = book.matchingFileName;
      if (name == null) continue;
      final key = coverMatchKey(name);
      counts[key] = (counts[key] ?? 0) + 1;
      final candidates = byName[key];
      if (candidates != null) matches.add(CoverMatch(book, candidates));
    }
    ambiguousBookKeys.addAll(counts.keys.where((k) => counts[k]! > 1));
    unmatchedImages.addAll(
      images.where((i) => !counts.containsKey(coverMatchKey(i.name))),
    );
  }
  final matches = <CoverMatch>[];
  final ambiguousBookKeys = <String>{};
  final unmatchedImages = <BookImportFile>[];
  bool needsChoice(CoverMatch match) =>
      match.images.length != 1 ||
      ambiguousBookKeys.contains(coverMatchKey(match.book.matchingFileName!));
}

class CoverBatchResult {
  int applied = 0;
  int skipped = 0;
  final failures = <String>[];
}

/// Recheck existence and covers under the library mutation lock. A stale preview
/// must never overwrite a newly assigned cover without the user's replace choice.
Future<CoverBatchResult> applyCoverMatches(
  BookRepository repository,
  Map<String, BookImportFile> selected, {
  required bool replaceExisting,
  void Function(int done, int total)? onProgress,
}) async {
  final result = CoverBatchResult();
  var done = 0;
  for (final entry in selected.entries) {
    try {
      await LibraryMutations.run(() async {
        final books = await repository.getBooks();
        final matches = books.where((b) => b.id == entry.key);
        if (matches.isEmpty ||
            (!replaceExisting && matches.first.coverPath != null)) {
          result.skipped++;
          return;
        }
        final path = entry.value.path;
        if (path == null || path.isEmpty) {
          throw const FormatException('이미지 경로 없음');
        }
        await repository.setBookCover(entry.key, path);
        result.applied++;
      });
    } catch (_) {
      result.failures.add(entry.value.name);
    }
    onProgress?.call(++done, selected.length);
  }
  return result;
}
