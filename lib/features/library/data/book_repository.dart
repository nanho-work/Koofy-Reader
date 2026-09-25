import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:koofy_reader/core/storage/library_mutations.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => LocalBookRepository(ref.watch(localStorageProvider)),
);

final booksProvider = FutureProvider<List<Book>>(
  (ref) => ref.watch(bookRepositoryProvider).getBooks(),
);

abstract class BookRepository {
  Future<List<Book>> getBooks();
  Future<Book?> importBookFile(String path);
  Future<void> saveDownloadedBook(Book book);
  Future<void> setBookCover(String bookId, String imagePath);
  Future<void> resetBookCover(String bookId);
  Future<bool> removeBookFromLibrary(String bookId);
  Future<bool> deleteLocalBook(String bookId);
}

class LocalBookRepository implements BookRepository {
  LocalBookRepository(
    this._storage, {
    BookCoverStore? covers,
    Future<Directory> Function()? sourceDirectory,
  }) : _covers = covers ?? BookCoverStore(_storage),
       _sourceDirectory = sourceDirectory ?? _defaultSourceDirectory;

  final Future<Directory> Function() _sourceDirectory;
  static Future<Directory> _defaultSourceDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/library_sources',
  );

  final LocalStorage _storage;
  final BookCoverStore _covers;
  static final List<Book> _books = [
    Book.asset(
      id: 'sample_1',
      title: '새벽의 쿠피',
      author: 'Koofy Studio',
      description: '오프라인에서도 바로 열 수 있는 샘플 소설',
      assetPath: 'assets/books/sample_1.txt',
    ),
    Book.asset(
      id: 'sample_2',
      title: '사용 방법 안내',
      author: 'Koofy Team',
      description: '앱 기능을 빠르게 익히는 사용자 가이드',
      assetPath: 'assets/books/sample_2.txt',
    ),
  ];

  @override
  Future<List<Book>> getBooks() => LibraryMutations.run(() async {
    final local = await _loadLocalBooks();
    final hiddenIds = await _loadHiddenBookIds();
    final visibleSamples = _books
        .where((book) => !hiddenIds.contains(book.id))
        .toList(growable: false);
    return _covers.apply([...local, ...visibleSamples]);
  });

  @override
  Future<void> setBookCover(String bookId, String imagePath) =>
      LibraryMutations.run(() async {
        if (!(await getBooks()).any((book) => book.id == bookId)) {
          throw StateError('표지를 바꿀 책을 찾지 못했습니다.');
        }
        await _covers.setImage(bookId, imagePath);
      });

  @override
  Future<void> resetBookCover(String bookId) => _covers.reset(bookId);

  @override
  Future<Book?> importBookFile(String path) => LibraryMutations.run(() async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    final lowerPath = path.toLowerCase();
    final isTxt = lowerPath.endsWith('.txt');
    final isEpub = lowerPath.endsWith('.epub');
    if (!isTxt && !isEpub) {
      return null;
    }

    final localBooks = await _loadLocalBooks();
    final duplicate = localBooks
        .where(
          (book) => book.localPath == path || book.importSourcePath == path,
        )
        .firstOrNull;
    if (duplicate != null) return duplicate;

    final fileName = _fileNameFromPath(path);
    var title = fileName.replaceAll(
      RegExp(r'\.(txt|epub)$', caseSensitive: false),
      '',
    );
    var author = '내 파일';
    final description = isEpub ? '로컬 파일에서 가져온 EPUB' : '로컬 파일에서 가져온 텍스트';

    final maximum = isEpub
        ? AppConstants.maxEpubBytes
        : AppConstants.maxTxtBytes;
    final length = await file.length();
    if (length <= 0 || length > maximum) {
      throw FormatException('비어 있지 않은 ${isEpub ? 40 : 20}MB 이하의 파일을 선택해 주세요.');
    }
    final bytes = await file.readAsBytes();
    final metadata = await ReadingPublicationPreparer.inspectImport(
      bytes,
      isEpub ? 'epub' : 'txt',
    );
    if (isEpub) {
      if (metadata.title != null && metadata.title!.trim().isNotEmpty) {
        title = metadata.title!.trim();
      }
      if (metadata.author != null && metadata.author!.trim().isNotEmpty) {
        author = metadata.author!.trim();
      }
    }

    final directory = await _sourceDirectory();
    await directory.create(recursive: true);
    final ownedDirectory = await directory.createTemp('book-');
    final owned = File(
      '${ownedDirectory.path}/source.${isEpub ? 'epub' : 'txt'}',
    );
    await owned.writeAsBytes(bytes, flush: true);
    final imported = Book.localFile(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      title: title.isEmpty ? '가져온 책' : title,
      author: author,
      description: description,
      localPath: owned.path,
      importSourcePath: path,
    );

    final next = [imported, ...localBooks];
    await _saveLocalBooks(next);
    return imported;
  });

  @override
  Future<void> saveDownloadedBook(Book book) => LibraryMutations.run(() async {
    if (!book.isLocalFile ||
        book.localPath == null ||
        !await File(book.localPath!).exists()) {
      throw StateError('다운로드한 책 파일을 찾을 수 없습니다.');
    }
    final current = await _loadLocalBooks();
    await _saveLocalBooks([
      book,
      ...current.where((existing) => existing.id != book.id),
    ]);
  });

  @override
  Future<bool> removeBookFromLibrary(String bookId) =>
      LibraryMutations.run(() async {
        final localDeleted = await deleteLocalBook(bookId);
        if (localDeleted) {
          return true;
        }
        final sampleExists = _books.any((book) => book.id == bookId);
        if (!sampleExists) {
          return false;
        }
        final hiddenIds = await _loadHiddenBookIds();
        if (hiddenIds.add(bookId)) {
          await _saveHiddenBookIds(hiddenIds);
        }
        await _covers.reset(bookId);
        return true;
      });

  @override
  Future<bool> deleteLocalBook(String bookId) => LibraryMutations.run(() async {
    final localBooks = await _loadLocalBooks();
    final exists = localBooks.any((book) => book.id == bookId);
    if (!exists) {
      return false;
    }

    final next = localBooks.where((book) => book.id != bookId).toList();
    await _saveLocalBooks(next);
    await _covers.reset(bookId);
    return true;
  });

  String _fileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }

  Future<List<Book>> _loadLocalBooks() async {
    final raw = await _storage.getString(AppConstants.localBooksKey);
    final backup = await _storage.getString(AppConstants.localBooksBackupKey);
    if ((raw == null || raw.isEmpty) && (backup == null || backup.isEmpty)) {
      return [];
    }
    final decoded = raw == null || raw.isEmpty ? null : _decodeLocalBooks(raw);
    if (decoded != null) return decoded;
    final recovered = backup == null || backup.isEmpty
        ? null
        : _decodeLocalBooks(backup);
    if (recovered != null) {
      if (raw != null && raw.isNotEmpty) {
        await _storage.setString(
          'library_corrupt_${DateTime.now().microsecondsSinceEpoch}',
          raw,
        );
      }
      await _storage.setString(AppConstants.localBooksKey, backup!);
      return recovered;
    }
    // Do not mistake damaged data for an empty library and overwrite both copies.
    throw const FormatException(
      '서재 목록이 손상되어 변경을 중단했습니다. 기존 기록은 보존했습니다. 백업 파일과 저장 공간을 확인해 주세요.',
    );
  }

  Future<void> _saveLocalBooks(List<Book> books) async {
    final jsonList = books.map((book) => book.toJson()).toList();
    final raw = jsonEncode(jsonList);
    await _storage.setString(AppConstants.localBooksKey, raw);
    await _storage.setString(AppConstants.localBooksBackupKey, raw);
  }

  Future<Set<String>> _loadHiddenBookIds() async {
    final raw = await _storage.getString(AppConstants.hiddenBooksKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <String>{};
      }
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveHiddenBookIds(Set<String> ids) async {
    final sorted = ids.toList()..sort();
    await _storage.setString(AppConstants.hiddenBooksKey, jsonEncode(sorted));
  }

  List<Book>? _decodeLocalBooks(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! List) {
        return null;
      }
      final result = <Book>[];
      final ids = <String>{};
      for (final item in json) {
        if (item is! Map<String, dynamic>) return null;
        final book = Book.fromJson(item);
        if (book == null ||
            !book.isLocalFile ||
            book.localPath == null ||
            book.localPath!.isEmpty ||
            !ids.add(book.id)) {
          return null;
        }
        result.add(book);
      }
      return result;
    } catch (_) {
      return null;
    }
  }
}
