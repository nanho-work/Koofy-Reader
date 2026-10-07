import 'dart:isolate';
import 'package:koofy_reader/features/library/domain/bundled_books.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'library_trash_store.dart';
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
  (ref) => LocalBookRepository(
    ref.watch(localStorageProvider),
    hasLegacyPublication: () async {
      final support = await getApplicationSupportDirectory();
      final key = sha256.convert(utf8.encode(BundledBooks.legacy.id));
      return File(
        '${support.path}/native_reader_v1/publications/references/$key.json',
      ).exists();
    },
  ),
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
    Future<bool> Function()? hasLegacyPublication,
    Future<Directory> Function()? sourceDirectory,
  }) : _hasLegacyPublication = hasLegacyPublication,
       _covers = covers ?? BookCoverStore(_storage),
       _sourceDirectory = sourceDirectory ?? _defaultSourceDirectory;

  final Future<Directory> Function() _sourceDirectory;
  static Future<Directory> _defaultSourceDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/library_sources',
  );

  final Future<bool> Function()? _hasLegacyPublication;
  final LocalStorage _storage;
  final BookCoverStore _covers;
  Future<bool> _retainLegacySample() async {
    if (await _storage.getString(BundledBooks.retainLegacyKey) == 'true') {
      return true;
    }
    final id = BundledBooks.legacy.id;
    final groups = await BookGroupRepository(_storage).load();
    final hasHistory =
        await _storage.getString('${AppConstants.readingProgressPrefix}$id') !=
            null ||
        await _storage.getString('${AppConstants.readingBookmarkPrefix}$id') !=
            null ||
        await _storage.getString('library_completion_v1:$id') != null ||
        await _storage.getString(
              'library_cover_${base64Url.encode(utf8.encode(id))}',
            ) !=
            null ||
        groups.any((group) => group.bookIds.contains(id)) ||
        (await _hasLegacyPublication?.call() ?? false);
    if (hasHistory) {
      await _storage.setString(BundledBooks.retainLegacyKey, 'true');
    }
    return hasHistory;
  }

  @override
  Future<List<Book>> getBooks() => LibraryMutations.run(() async {
    final local = await _loadLocalBooks();
    final hiddenIds = {
      ...await _loadHiddenBookIds(),
      ...await LibraryTrashStore(_storage).hiddenBookIds(),
    };
    final bundled = [
      ...BundledBooks.defaults,
      if (await _retainLegacySample()) BundledBooks.legacy,
    ];
    final visibleSamples = bundled
        .where((book) => !hiddenIds.contains(book.id))
        .toList(growable: false);
    return _covers.apply([
      ...local.where((b) => !hiddenIds.contains(b.id)),
      ...visibleSamples,
    ]);
  });

  Future<List<Book>> allStoredBooks() async => [
    ...await _loadLocalBooks(),
    ...BundledBooks.defaults,
    BundledBooks.legacy,
  ];

  Future<void> forgetPermanently(Set<String> ids) =>
      LibraryMutations.run(() async {
        await _saveLocalBooks(
          (await _loadLocalBooks())
              .where((book) => !ids.contains(book.id))
              .toList(),
        );
        final hidden = await _loadHiddenBookIds();
        hidden.addAll(ids.where(BundledBooks.ids.contains));
        await _saveHiddenBookIds(hidden);
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
  Future<Book?> importBookFile(String path) => _import(path);

  Future<Book?> importNormalizedText(String path, String text) =>
      _import(path, normalized: Uint8List.fromList(utf8.encode(text)));

  Future<Book?> _import(
    String path, {
    Uint8List? normalized,
  }) => LibraryMutations.run(() async {
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
    final bytes = normalized ?? await file.readAsBytes();
    if (bytes.length > maximum) {
      throw const FormatException('변환된 책의 용량이 제한을 초과했습니다.');
    }
    final fingerprint = await _fingerprint(bytes);
    final hidden = await LibraryTrashStore(_storage).hiddenBookIds();
    for (final existing in localBooks.where((b) => !hidden.contains(b.id))) {
      var hash = existing.sourceHash;
      if (hash == null && existing.localPath != null) {
        final prior = File(existing.localPath!);
        if (await prior.exists() && await prior.length() == bytes.length) {
          hash = (await sha256.bind(prior.openRead()).first).toString();
        }
      }
      if (hash == fingerprint &&
          existing.localPath?.toLowerCase().endsWith(
                isEpub ? '.epub' : '.txt',
              ) ==
              true) {
        return existing;
      }
    }
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
      originalFileName: fileName,
      sourceHash: fingerprint,
    );

    final next = [imported, ...localBooks];
    await _saveLocalBooks(next);
    return imported;
  });

  @override
  Future<void> saveDownloadedBook(Book book) => LibraryMutations.run(() async {
    await LibraryTrashStore(_storage).ensureRestorable(book.id);
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
    // An explicit download must make a previously trashed catalog book visible.
    await LibraryTrashStore(_storage).restoreBook(book.id);
  });

  @override
  Future<bool> removeBookFromLibrary(String bookId) =>
      LibraryMutations.run(() async {
        final localDeleted = await deleteLocalBook(bookId);
        if (localDeleted) {
          return true;
        }
        final sampleExists = BundledBooks.ids.contains(bookId);
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

Future<String> _fingerprint(Uint8List bytes) =>
    Isolate.run(() => sha256.convert(bytes).toString());
