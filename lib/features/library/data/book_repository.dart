import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
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
  Future<String> readBookContent(Book book);
  Future<Book?> importBookFile(String path);
}

class LocalBookRepository implements BookRepository {
  LocalBookRepository(this._storage);

  final LocalStorage _storage;
  static const int _maxTxtBytes = 20 * 1024 * 1024;
  static const int _maxEpubBytes = 40 * 1024 * 1024;

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
      title: '리더 빌드 노트',
      author: 'Koofy Team',
      description: '북리더 MVP 설계와 개발 메모',
      assetPath: 'assets/books/sample_2.txt',
    ),
  ];

  @override
  Future<List<Book>> getBooks() async {
    final local = await _loadLocalBooks();
    return [...local, ..._books];
  }

  @override
  Future<String> readBookContent(Book book) async {
    if (book.sourceType == BookSourceType.asset) {
      final path = book.assetPath;
      if (path == null) {
        throw Exception('assetPath is missing for ${book.id}');
      }
      return rootBundle.loadString(path);
    }

    final path = book.localPath;
    if (path == null) {
      throw Exception('localPath is missing for ${book.id}');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('파일을 찾을 수 없습니다: $path');
    }

    final isEpub = path.toLowerCase().endsWith('.epub');
    final fileLength = await file.length();
    if (isEpub && fileLength > _maxEpubBytes) {
      throw Exception('EPUB 용량이 너무 큽니다. 40MB 이하 파일을 사용해 주세요.');
    }
    if (!isEpub && fileLength > _maxTxtBytes) {
      throw Exception('TXT 용량이 너무 큽니다. 20MB 이하 파일을 사용해 주세요.');
    }

    if (isEpub) {
      return _readEpubContent(file);
    }
    return file.readAsString();
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

  Future<String> _readEpubContent(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final filesByPath = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      filesByPath[_normalizePath(entry.name)] = entry;
    }

    final readingOrder = _resolveEpubReadingOrder(filesByPath);
    final chapterPaths = readingOrder.isNotEmpty
        ? readingOrder
        : _fallbackChapterOrder(filesByPath.keys.toList());

    if (chapterPaths.isEmpty) {
      throw Exception('EPUB에서 본문 파일을 찾지 못했습니다.');
    }

    final buffer = StringBuffer();
    for (final chapterPath in chapterPaths) {
      final chapterFile = filesByPath[_normalizePath(chapterPath)];
      if (chapterFile == null) {
        continue;
      }
      final raw = utf8.decode(chapterFile.content, allowMalformed: true);
      final text = _stripHtml(raw);
      if (text.trim().isNotEmpty) {
        buffer.writeln(text.trim());
        buffer.writeln();
      }
    }

    final content = buffer.toString().trim();
    if (content.isEmpty) {
      throw Exception('EPUB 본문 추출 결과가 비어 있습니다.');
    }
    return content;
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

  List<String> _resolveEpubReadingOrder(Map<String, ArchiveFile> filesByPath) {
    final opfPath = _resolveOpfPath(filesByPath);
    if (opfPath == null) {
      return const [];
    }
    final opfFile = filesByPath[opfPath];
    if (opfFile == null) {
      return const [];
    }

    try {
      final opfXml = utf8.decode(opfFile.content, allowMalformed: true);
      final opfDoc = XmlDocument.parse(opfXml);
      final baseDir = _dirName(opfPath);

      final manifestById = <String, String>{};
      for (final item in opfDoc.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id == null || href == null || href.trim().isEmpty) {
          continue;
        }
        manifestById[id] = _joinPath(baseDir, href);
      }

      final ordered = <String>[];
      for (final itemref in opfDoc.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        if (idref == null) {
          continue;
        }
        final href = manifestById[idref];
        if (href == null) {
          continue;
        }
        if (filesByPath.containsKey(href)) {
          ordered.add(href);
        }
      }
      return ordered;
    } catch (_) {
      return const [];
    }
  }

  List<String> _fallbackChapterOrder(List<String> paths) {
    final filtered =
        paths
            .where(
              (path) =>
                  path.endsWith('.xhtml') ||
                  path.endsWith('.html') ||
                  path.endsWith('.htm'),
            )
            .toList()
          ..sort();
    return filtered;
  }

  String _stripHtml(String html) {
    try {
      final doc = XmlDocument.parse(html);
      final body = doc.findAllElements('body');
      if (body.isNotEmpty) {
        final text = body.first.innerText;
        return _normalizeWhitespace(text);
      }
      return _normalizeWhitespace(doc.innerText);
    } catch (_) {
      final withoutScript = html
          .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
            ' ',
          )
          .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
            ' ',
          );
      final withoutTags = withoutScript.replaceAll(RegExp(r'<[^>]+>'), ' ');
      return _normalizeWhitespace(withoutTags);
    }
  }

  String _normalizeWhitespace(String input) {
    final collapsed = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[\t\f\v ]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return collapsed;
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

  String _dirName(String path) {
    final index = path.lastIndexOf('/');
    if (index < 0) {
      return '';
    }
    return path.substring(0, index);
  }

  String _joinPath(String baseDir, String child) {
    if (baseDir.isEmpty) {
      return _normalizePath(child);
    }
    return _normalizePath('$baseDir/$child');
  }
}

class _EpubMetadata {
  const _EpubMetadata({this.title, this.author});

  final String? title;
  final String? author;
}
