import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:xml/xml.dart';

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
  Future<bool> removeBookFromLibrary(String bookId);
  Future<bool> deleteLocalBook(String bookId);
}

class LocalBookRepository implements BookRepository {
  LocalBookRepository(this._storage);

  final LocalStorage _storage;
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
  Future<List<Book>> getBooks() async {
    final local = await _loadLocalBooks();
    final hiddenIds = await _loadHiddenBookIds();
    final visibleSamples = _books
        .where((book) => !hiddenIds.contains(book.id))
        .toList(growable: false);
    return [...local, ...visibleSamples];
  }

  @override
  Future<Book?> importBookFile(String path) async {
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
    final duplicate = localBooks.any((book) => book.localPath == path);
    if (duplicate) {
      return localBooks.firstWhere((book) => book.localPath == path);
    }

    final fileName = _fileNameFromPath(path);
    var title = fileName.replaceAll(
      RegExp(r'\.(txt|epub)$', caseSensitive: false),
      '',
    );
    var author = '내 파일';
    final description = isEpub ? '로컬 파일에서 가져온 EPUB' : '로컬 파일에서 가져온 텍스트';

    if (isEpub) {
      final metadata = await _readEpubMetadata(file);
      if (metadata.title != null && metadata.title!.trim().isNotEmpty) {
        title = metadata.title!.trim();
      }
      if (metadata.author != null && metadata.author!.trim().isNotEmpty) {
        author = metadata.author!.trim();
      }
    }

    final imported = Book.localFile(
      id: 'local_${DateTime.now().microsecondsSinceEpoch}',
      title: title.isEmpty ? '가져온 책' : title,
      author: author,
      description: description,
      localPath: path,
    );

    final next = [imported, ...localBooks];
    await _saveLocalBooks(next);
    return imported;
  }

  @override
  Future<void> saveDownloadedBook(Book book) async {
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
  }

  @override
  Future<bool> removeBookFromLibrary(String bookId) async {
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
    return true;
  }

  @override
  Future<bool> deleteLocalBook(String bookId) async {
    final localBooks = await _loadLocalBooks();
    final exists = localBooks.any((book) => book.id == bookId);
    if (!exists) {
      return false;
    }

    final next = localBooks.where((book) => book.id != bookId).toList();
    await _saveLocalBooks(next);
    return true;
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isEmpty ? path : parts.last;
  }

  Future<List<Book>> _loadLocalBooks() async {
    final raw = await _storage.getString(AppConstants.localBooksKey);
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final decoded = _decodeLocalBooks(raw);
    if (decoded != null) {
      return decoded;
    }

    final backupRaw = await _storage.getString(
      AppConstants.localBooksBackupKey,
    );
    if (backupRaw == null || backupRaw.trim().isEmpty) {
      return const [];
    }
    final recovered = _decodeLocalBooks(backupRaw);
    if (recovered != null) {
      await _storage.setString(AppConstants.localBooksKey, backupRaw);
      return recovered;
    }
    return const [];
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
      return json
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .map(Book.fromJson)
          .whereType<Book>()
          .where((book) => book.sourceType == BookSourceType.localFile)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<_EpubMetadata> _readEpubMetadata(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final filesByPath = <String, ArchiveFile>{};
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        filesByPath[_normalizePath(entry.name)] = entry;
      }

      final opfPath = _resolveOpfPath(filesByPath);
      if (opfPath == null) {
        return const _EpubMetadata();
      }
      final opfFile = filesByPath[opfPath];
      if (opfFile == null) {
        return const _EpubMetadata();
      }

      final opfXml = utf8.decode(opfFile.content, allowMalformed: true);
      final opfDoc = XmlDocument.parse(opfXml);

      String? title;
      for (final element in _elementsByName(opfDoc, 'title')) {
        final value = element.innerText.trim();
        if (value.isNotEmpty) {
          title = value;
          break;
        }
      }

      String? author;
      for (final element in _elementsByName(opfDoc, 'creator')) {
        final value = element.innerText.trim();
        if (value.isNotEmpty) {
          author = value;
          break;
        }
      }

      return _EpubMetadata(title: title, author: author);
    } catch (_) {
      return const _EpubMetadata();
    }
  }

  String? _resolveOpfPath(Map<String, ArchiveFile> filesByPath) {
    const containerPath = 'meta-inf/container.xml';
    final container = filesByPath[containerPath];
    if (container != null) {
      try {
        final containerXml = utf8.decode(
          container.content,
          allowMalformed: true,
        );
        final doc = XmlDocument.parse(containerXml);
        final rootfiles = doc.findAllElements('rootfile');
        for (final rootfile in rootfiles) {
          final fullPath = rootfile.getAttribute('full-path');
          if (fullPath == null || fullPath.trim().isEmpty) {
            continue;
          }
          final normalized = _normalizePath(fullPath);
          if (filesByPath.containsKey(normalized)) {
            return normalized;
          }
        }
      } catch (_) {
        // Continue with fallback below.
      }
    }

    for (final path in filesByPath.keys) {
      if (path.endsWith('.opf')) {
        return path;
      }
    }
    return null;
  }

  Iterable<XmlElement> _elementsByName(XmlDocument doc, String localName) {
    return doc.descendants.whereType<XmlElement>().where(
      (element) => element.name.local.toLowerCase() == localName,
    );
  }

  String _normalizePath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final segments = <String>[];
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (segments.isNotEmpty) {
          segments.removeLast();
        }
        continue;
      }
      segments.add(segment);
    }
    return segments.join('/');
  }
}

class _EpubMetadata {
  const _EpubMetadata({this.title, this.author});

  final String? title;
  final String? author;
}
