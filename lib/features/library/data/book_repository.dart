import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/core/services/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

final bookRepositoryProvider = Provider<BookRepository>(
  (ref) => LocalBookRepository(ref.watch(localStorageProvider)),
);

final booksProvider = FutureProvider<List<Book>>(
  (ref) => ref.watch(bookRepositoryProvider).getBooks(),
);

abstract class BookRepository {
  Future<List<Book>> getBooks();
  Future<PreparedBookContent> readPreparedBookContent(Book book);
  Future<String> readBookContent(Book book);
  Future<Book?> importBookFile(String path);
}

class PreparedBookContent {
  const PreparedBookContent({
    required this.content,
    required this.contentHash,
    required this.structureIndex,
  });

  final String content;
  final String contentHash;
  final ReaderStructureIndex structureIndex;
}

class LocalBookRepository implements BookRepository {
  LocalBookRepository(this._storage);

  final LocalStorage _storage;
  static const int _contentCacheSchemaVersion = 3;
  static final Map<String, _InMemoryContentCacheEntry> _inMemoryContentCache =
      <String, _InMemoryContentCacheEntry>{};

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
    final prepared = await readPreparedBookContent(book);
    return prepared.content;
  }

  @override
  Future<PreparedBookContent> readPreparedBookContent(Book book) async {
    String sourceStamp;
    String normalizedContent;

    if (book.sourceType == BookSourceType.asset) {
      final path = book.assetPath;
      if (path == null) {
        throw Exception('assetPath is missing for ${book.id}');
      }
      sourceStamp = 'asset:$path';
      final inMemory = _readInMemoryContentCache(
        bookId: book.id,
        sourceStamp: sourceStamp,
      );
      if (inMemory != null) {
        return inMemory;
      }
      final cached = await _readNormalizedContentCache(
        bookId: book.id,
        sourceStamp: sourceStamp,
      );
      if (cached != null) {
        await _writeNormalizedContentCache(
          bookId: book.id,
          sourceStamp: sourceStamp,
          prepared: cached,
        );
        _writeInMemoryContentCache(
          bookId: book.id,
          sourceStamp: sourceStamp,
          prepared: cached,
        );
        return cached;
      }
      normalizedContent = _normalizeContent(await rootBundle.loadString(path));
      final prepared = _buildPreparedBookContent(normalizedContent);
      await _writeNormalizedContentCache(
        bookId: book.id,
        sourceStamp: sourceStamp,
        prepared: prepared,
      );
      _writeInMemoryContentCache(
        bookId: book.id,
        sourceStamp: sourceStamp,
        prepared: prepared,
      );
      return prepared;
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
    final stat = await file.stat();
    final fileLength = stat.size;
    if (isEpub && fileLength > AppConstants.maxEpubBytes) {
      throw Exception('EPUB 용량이 너무 큽니다. 40MB 이하 파일을 사용해 주세요.');
    }
    if (!isEpub && fileLength > AppConstants.maxTxtBytes) {
      throw Exception('TXT 용량이 너무 큽니다. 20MB 이하 파일을 사용해 주세요.');
    }

    sourceStamp =
        'local:$path:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    final inMemory = _readInMemoryContentCache(
      bookId: book.id,
      sourceStamp: sourceStamp,
    );
    if (inMemory != null) {
      return inMemory;
    }
    final cached = await _readNormalizedContentCache(
      bookId: book.id,
      sourceStamp: sourceStamp,
    );
    if (cached != null) {
      await _writeNormalizedContentCache(
        bookId: book.id,
        sourceStamp: sourceStamp,
        prepared: cached,
      );
      _writeInMemoryContentCache(
        bookId: book.id,
        sourceStamp: sourceStamp,
        prepared: cached,
      );
      return cached;
    }

    if (isEpub) {
      normalizedContent = _normalizeContent(await _readEpubContent(file));
    } else {
      normalizedContent = _normalizeContent(await file.readAsString());
    }
    final prepared = _buildPreparedBookContent(normalizedContent);
    await _writeNormalizedContentCache(
      bookId: book.id,
      sourceStamp: sourceStamp,
      prepared: prepared,
    );
    _writeInMemoryContentCache(
      bookId: book.id,
      sourceStamp: sourceStamp,
      prepared: prepared,
    );
    return prepared;
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
    return Isolate.run(() => _extractEpubContentFromBytes(bytes));
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

  String _normalizeContent(String raw) {
    return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  PreparedBookContent? _readInMemoryContentCache({
    required String bookId,
    required String sourceStamp,
  }) {
    final entry = _inMemoryContentCache[bookId];
    if (entry == null || entry.sourceStamp != sourceStamp) {
      return null;
    }
    return PreparedBookContent(
      content: entry.content,
      contentHash: entry.contentHash,
      structureIndex: entry.structureIndex,
    );
  }

  void _writeInMemoryContentCache({
    required String bookId,
    required String sourceStamp,
    required PreparedBookContent prepared,
  }) {
    _inMemoryContentCache.remove(bookId);
    _inMemoryContentCache[bookId] = _InMemoryContentCacheEntry(
      sourceStamp: sourceStamp,
      content: prepared.content,
      contentHash: prepared.contentHash,
      structureIndex: prepared.structureIndex,
    );
    const maxEntries = 3;
    while (_inMemoryContentCache.length > maxEntries) {
      final oldestKey = _inMemoryContentCache.keys.first;
      _inMemoryContentCache.remove(oldestKey);
    }
  }

  Future<PreparedBookContent?> _readNormalizedContentCache({
    required String bookId,
    required String sourceStamp,
  }) async {
    try {
      final file = await _contentCacheFileFor(bookId);
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final schema = decoded['schemaVersion'];
      final cachedStamp = decoded['sourceStamp'];
      final content = decoded['normalizedContent'];
      final contentHash = decoded['contentHash'];
      final structureIndexRaw = decoded['structureIndex'];
      if (schema is! int || schema < 1 || schema > _contentCacheSchemaVersion) {
        return null;
      }
      if (cachedStamp is! String || cachedStamp != sourceStamp) {
        return null;
      }
      if (content is! String) {
        return null;
      }
      return _buildPreparedBookContent(
        content,
        existingHash: contentHash is String ? contentHash : null,
        existingStructureIndex: structureIndexRaw is String
            ? ReaderStructureIndex.fromRaw(structureIndexRaw)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeNormalizedContentCache({
    required String bookId,
    required String sourceStamp,
    required PreparedBookContent prepared,
  }) async {
    try {
      final file = await _contentCacheFileFor(bookId);
      await file.parent.create(recursive: true);
      final payload = jsonEncode({
        'schemaVersion': _contentCacheSchemaVersion,
        'sourceStamp': sourceStamp,
        'normalizedContent': prepared.content,
        'contentHash': prepared.contentHash,
        'structureIndex': prepared.structureIndex.toRaw(),
      });
      await file.writeAsString(payload, flush: true);
    } catch (_) {
      // Fallback to raw read path if cache write fails.
    }
  }

  PreparedBookContent _buildPreparedBookContent(
    String normalizedContent, {
    String? existingHash,
    ReaderStructureIndex? existingStructureIndex,
  }) {
    final contentHash = existingHash ?? _stableHash(normalizedContent);
    final structureIndex =
        _isCompatibleStructureIndex(
          existingStructureIndex,
          contentLength: normalizedContent.length,
          contentHash: contentHash,
        )
        ? existingStructureIndex!
        : _buildStructureIndex(
            content: normalizedContent,
            contentHash: contentHash,
          );
    return PreparedBookContent(
      content: normalizedContent,
      contentHash: contentHash,
      structureIndex: structureIndex,
    );
  }

  bool _isCompatibleStructureIndex(
    ReaderStructureIndex? structureIndex, {
    required int contentLength,
    required String contentHash,
  }) {
    if (structureIndex == null) {
      return false;
    }
    return structureIndex.contentLength == contentLength &&
        structureIndex.contentHash == contentHash &&
        structureIndex.paragraphs.isNotEmpty;
  }

  ReaderStructureIndex _buildStructureIndex({
    required String content,
    required String contentHash,
  }) {
    final contentIndex = ReaderContentIndexer.buildFromContent(content);
    return ReaderStructureIndex(
      schemaVersion: ReaderStructureIndex.currentSchemaVersion,
      contentLength: content.length,
      contentHash: contentHash,
      paragraphs: contentIndex.paragraphRanges
          .map(
            (range) =>
                ReaderParagraphRangeData(start: range.start, end: range.end),
          )
          .toList(growable: false),
      chapters: contentIndex.chapterRanges
          .map(
            (range) => ReaderChapterRangeData(
              id: range.id,
              paragraphStartIndex: range.paragraphStartIndex,
              paragraphEndIndex: range.paragraphEndIndex,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<File> _contentCacheFileFor(String bookId) async {
    final baseDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${baseDir.path}/reader_content_cache');
    final fileId = _stableHash(bookId);
    return File('${cacheDir.path}/$fileId.json');
  }

  String _stableHash(String value) {
    const int fnvOffsetBasis = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffsetBasis;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _InMemoryContentCacheEntry {
  const _InMemoryContentCacheEntry({
    required this.sourceStamp,
    required this.content,
    required this.contentHash,
    required this.structureIndex,
  });

  final String sourceStamp;
  final String content;
  final String contentHash;
  final ReaderStructureIndex structureIndex;
}

String _extractEpubContentFromBytes(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes, verify: false);
  final filesByPath = <String, ArchiveFile>{};
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    filesByPath[_normalizePathWorker(entry.name)] = entry;
  }

  final readingOrder = _resolveEpubReadingOrderWorker(filesByPath);
  final chapterPaths = readingOrder.isNotEmpty
      ? readingOrder
      : _fallbackChapterOrderWorker(filesByPath.keys.toList());

  if (chapterPaths.isEmpty) {
    throw Exception('EPUB에서 본문 파일을 찾지 못했습니다.');
  }

  final buffer = StringBuffer();
  for (final chapterPath in chapterPaths) {
    final chapterFile = filesByPath[_normalizePathWorker(chapterPath)];
    if (chapterFile == null) {
      continue;
    }
    final raw = utf8.decode(chapterFile.content, allowMalformed: true);
    final text = _stripHtmlWorker(raw);
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

List<String> _resolveEpubReadingOrderWorker(
  Map<String, ArchiveFile> filesByPath,
) {
  final opfPath = _resolveOpfPathWorker(filesByPath);
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
    final baseDir = _dirNameWorker(opfPath);

    final manifestById = <String, String>{};
    for (final item in opfDoc.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null || href.trim().isEmpty) {
        continue;
      }
      manifestById[id] = _joinPathWorker(baseDir, href);
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

String? _resolveOpfPathWorker(Map<String, ArchiveFile> filesByPath) {
  const containerPath = 'meta-inf/container.xml';
  final container = filesByPath[containerPath];
  if (container != null) {
    try {
      final containerXml = utf8.decode(container.content, allowMalformed: true);
      final doc = XmlDocument.parse(containerXml);
      final rootfiles = doc.findAllElements('rootfile');
      for (final rootfile in rootfiles) {
        final fullPath = rootfile.getAttribute('full-path');
        if (fullPath == null || fullPath.trim().isEmpty) {
          continue;
        }
        final normalized = _normalizePathWorker(fullPath);
        if (filesByPath.containsKey(normalized)) {
          return normalized;
        }
      }
    } catch (_) {
      // Continue fallback below.
    }
  }

  for (final path in filesByPath.keys) {
    if (path.endsWith('.opf')) {
      return path;
    }
  }
  return null;
}

List<String> _fallbackChapterOrderWorker(List<String> paths) {
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

String _stripHtmlWorker(String html) {
  try {
    final doc = XmlDocument.parse(html);
    final body = doc.findAllElements('body');
    if (body.isNotEmpty) {
      final text = body.first.innerText;
      return _normalizeWhitespaceWorker(text);
    }
    return _normalizeWhitespaceWorker(doc.innerText);
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
    return _normalizeWhitespaceWorker(withoutTags);
  }
}

String _normalizeWhitespaceWorker(String input) {
  return input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[\t\f\v ]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _normalizePathWorker(String path) {
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

String _dirNameWorker(String path) {
  final index = path.lastIndexOf('/');
  if (index < 0) {
    return '';
  }
  return path.substring(0, index);
}

String _joinPathWorker(String baseDir, String child) {
  if (baseDir.isEmpty) {
    return _normalizePathWorker(child);
  }
  return _normalizePathWorker('$baseDir/$child');
}

class _EpubMetadata {
  const _EpubMetadata({this.title, this.author});

  final String? title;
  final String? author;
}
