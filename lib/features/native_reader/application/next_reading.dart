import 'dart:io';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/domain/bundled_books.dart';

enum NextReadingKind { local, download, upcoming, waiting, completed }

class NextReading {
  const NextReading(
    this.kind, {
    this.book,
    this.item,
    this.groupEnd = false,
    this.seriesEnd = false,
    this.afterEpisode,
  });
  final NextReadingKind kind;
  final Book? book;
  final CatalogItem? item;
  final bool groupEnd;
  final bool seriesEnd;
  final int? afterEpisode;
}

/// One continuation policy for both native viewers. Local collections use only
/// their explicit order; catalog chapters use public series/episode identity.
class NextReadingResolver {
  NextReadingResolver(this.catalog);
  final ReaderCatalog catalog;

  static bool hasRemoteSource(Book book) =>
      book.id.startsWith('catalog_') || BundledBooks.hasContinuation(book);

  static Future<Book?> existingBook(CatalogItem item, List<Book> books) async {
    final candidates = books.where(
      (book) =>
          book.id == item.bookId ||
          RegExp('^catalog_${item.id}_[0-9]+\$').hasMatch(book.id),
    );
    // Reuse a previously downloaded edition and its reading position first.
    for (final book in candidates) {
      if (!book.isLocalFile ||
          (book.localPath != null && await File(book.localPath!).exists())) {
        return book;
      }
    }
    return null;
  }

  static Future<NextReading> local(
    Book current,
    List<Book> books,
    List<BookGroup> groups,
  ) async {
    for (final group in groups) {
      final index = group.bookIds.indexOf(current.id);
      if (index < 0) continue;
      if (index + 1 < group.bookIds.length) {
        final id = group.bookIds[index + 1];
        final next = books.where((book) => book.id == id).firstOrNull;
        if (next != null &&
            (!next.isLocalFile ||
                (next.localPath != null &&
                    await File(next.localPath!).exists()))) {
          return NextReading(NextReadingKind.local, book: next);
        }
      }
      return const NextReading(NextReadingKind.completed, groupEnd: true);
    }
    return const NextReading(NextReadingKind.completed);
  }

  static Future<NextReading?> installedSuccessor(
    CatalogItem? source,
    List<Book> books,
  ) async {
    if (source?.seriesId == null || source?.episodeNumber == null) return null;
    for (final book in books) {
      final meta = book.catalogMetadata;
      if (meta == null ||
          meta['seriesId'] != source!.seriesId ||
          meta['episodeNumber'] != source.episodeNumber! + 1) {
        continue;
      }
      final candidate = CatalogItem.fromJson(meta);
      final saved = await existingBook(candidate, [book]);
      if (saved != null) {
        return NextReading(NextReadingKind.local, book: saved, item: candidate);
      }
    }
    return null;
  }

  Future<NextReading> resolve(
    Book current,
    List<Book> books,
    List<BookGroup> groups,
  ) async {
    final personalGroups = groups
        .where((group) => group.catalogSeriesId == null)
        .toList();
    if (!hasRemoteSource(current) ||
        personalGroups.any((group) => group.bookIds.contains(current.id))) {
      return local(current, books, personalGroups);
    }
    final source = BundledBooks.hasContinuation(current)
        ? null
        : await catalog.sourceForBook(current);
    String? seriesId = source?.seriesId;
    var number = source?.episodeNumber;
    final language =
        source?.json['language'] as String? ??
        (BundledBooks.hasContinuation(current)
            ? BundledBooks.languageOf(current)
            : null);
    if (BundledBooks.hasContinuation(current)) {
      final title = switch (language) {
        'en' => 'The Mermaid Princess Cuts the Waves',
        'ja' => '人魚姫は波を斬る',
        _ => '인어공주는 파도를 벤다',
      };
      final works = await catalog.completeItems('book', language: language);
      seriesId = works
          .where((item) => item.kind == 'series' && item.title == title)
          .firstOrNull
          ?.id;
      number = 1;
      if (seriesId == null) return const NextReading(NextReadingKind.waiting);
    } else if (source == null) {
      throw const CatalogException(
        '작품 정보를 확인하지 못했습니다. 도서에서 작품 정보를 다시 확인해 주세요.',
      );
    }
    if (seriesId == null || number == null) {
      return const NextReading(NextReadingKind.completed);
    }
    final offline = await installedSuccessor(source, books);
    if (offline != null) return offline;
    final episodes = await catalog.completeItems(
      'series:$seriesId',
      language: language,
    );
    final following =
        episodes
            .where(
              (item) =>
                  item.episodeNumber != null && item.episodeNumber! > number!,
            )
            .toList()
          ..sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
    if (following.isNotEmpty) {
      final item = following.first;
      final saved = await existingBook(item, books);
      if (saved != null) {
        return NextReading(NextReadingKind.local, book: saved, item: item);
      }
      return NextReading(
        item.upcoming ? NextReadingKind.upcoming : NextReadingKind.download,
        item: item,
        afterEpisode: number,
      );
    }
    final works = await catalog.completeItems('book', language: language);
    final parent = works.where((item) => item.id == seriesId).firstOrNull;
    if (parent == null) {
      throw const CatalogException(
        '작품 정보를 확인하지 못했습니다. 도서에서 작품 정보를 다시 확인해 주세요.',
      );
    }
    return NextReading(
      parent.seriesStatus == 'completed'
          ? NextReadingKind.completed
          : NextReadingKind.waiting,
      seriesEnd: true,
    );
  }
}
