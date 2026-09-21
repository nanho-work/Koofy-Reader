import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';

class MemoryStorage implements LocalStorage {
  final values = <String, String>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<int?> getInt(String key) async => int.tryParse(values[key] ?? '');
  @override
  Future<void> setInt(String key, int value) async {
    values[key] = '$value';
  }

  @override
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix) async =>
      Map.fromEntries(values.entries.where((e) => e.key.startsWith(prefix)));
}

void main() {
  late Directory directory;
  late HttpServer server;
  late ReaderCatalog catalog;
  late LocalBookRepository books;
  var corrupt = false;
  var textBooks = false;
  final requestedSlots = <String>[];
  String? requestedTxtSupport;
  final files = {
    'preview': base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2h0sAAAAASUVORK5CYII=',
    ),
    'epub': utf8.encode('epub test bytes'),
    'txt': utf8.encode('다운로드한 한글 책\n\n다음 문단 😀'),
    'cover': utf8.encode('cover test bytes'),
    'font400': utf8.encode('OTTO verified test font'),
  };
  Map<String, dynamic> asset(String slot) => {
    'sha256': sha256.convert(files[slot]!).toString(),
    'size': files[slot]!.length,
    'extension': slot == 'preview'
        ? 'png'
        : slot == 'font400'
        ? 'otf'
        : slot == 'cover'
        ? 'webp'
        : slot,
    if (slot == 'font400') 'weight': 400,
  };
  Map<String, dynamic> itemJson(String kind, {int version = 1}) => {
    'id': 'a' * 32,
    'kind': kind,
    'title': '테스트',
    'author': '제작자',
    'description': '',
    'license': '배포 허가',
    'version': version,
    'assets': kind == 'book'
        ? {
            if (textBooks) 'txt': asset('txt') else 'epub': asset('epub'),
            'cover': asset('cover'),
          }
        : {'font400': asset('font400')},
  };
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader_catalog_test_');
    books = LocalBookRepository(MemoryStorage());
    corrupt = false;
    textBooks = false;
    requestedTxtSupport = null;
    requestedSlots.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/file') {
        final bytes = files[request.uri.queryParameters['slot']]!;
        request.response.add(corrupt ? List.filled(bytes.length, 0) : bytes);
      } else if (request.uri.queryParameters['action'] == 'download') {
        final slot = request.uri.queryParameters['slot']!;
        requestedSlots.add(slot);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            ...asset(slot),
            'url': 'http://127.0.0.1:${server.port}/file?slot=$slot',
          }),
        );
      } else {
        requestedTxtSupport = request.uri.queryParameters['supportsTxt'];
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'items': [itemJson(request.uri.queryParameters['kind']!)],
            'nextCursor': null,
          }),
        );
      }
      await request.response.close();
    });
    catalog = ReaderCatalog(
      books,
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/catalog'),
      directory: () async => directory,
    );
  });
  tearDown(() async {
    catalog.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
    'preview fetches only a PNG and reuses its verified cache without installing fonts',
    () async {
      final item = CatalogItem.fromJson({
        ...itemJson('font'),
        'preview': asset('preview'),
      });
      expect(await catalog.fontPreview(item), files['preview']);
      expect(await catalog.fontPreview(item), files['preview']);
      expect(requestedSlots, ['preview']);
      expect(await catalog.isInstalled(item), false);
      expect(
        await File(
          '${directory.path}/cloud_reader/fonts/catalog.json',
        ).exists(),
        false,
      );
    },
  );
  test(
    'corrupt previews are rejected and legacy catalogs require no preview request',
    () async {
      expect(
        await catalog.fontPreview(CatalogItem.fromJson(itemJson('font'))),
        isNull,
      );
      expect(requestedSlots, isEmpty);
      corrupt = true;
      await expectLater(
        catalog.fontPreview(
          CatalogItem.fromJson({
            ...itemJson('font'),
            'preview': asset('preview'),
          }),
        ),
        throwsA(isA<CatalogException>()),
      );
      expect(
        await catalog.isInstalled(CatalogItem.fromJson(itemJson('font'))),
        false,
      );
      expect(
        () => CatalogItem.fromJson({
          ...itemJson('font'),
          'preview': {...asset('preview'), 'size': 128 * 1024 + 1},
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'TXT is discovered, downloaded and prepared for the native reader offline',
    () async {
      textBooks = true;
      final item = (await catalog.list('book')).items.single;
      expect(requestedTxtSupport, '1');
      await catalog.install(item);
      final book = (await books.getBooks()).singleWhere(
        (b) => b.id == item.bookId,
      );
      expect(book.localPath, endsWith('.txt'));
      expect(await File(book.localPath!).readAsBytes(), files['txt']);
      expect(await File(book.coverPath!).readAsBytes(), files['cover']);
      catalog.close();
      final preparer = ReadingPublicationPreparer(
        storageDirectory: Directory('${directory.path}/prepared'),
      );
      final prepared = await preparer.prepare(book: book);
      final repeated = await preparer.prepare(
        book: Book.fromJson(book.toJson())!,
      );
      expect(prepared.publicationId, item.bookId);
      expect(prepared.textMap, isNotNull);
      expect(await File(prepared.filePath).exists(), true);
      expect(repeated.contentRevision, prepared.contentRevision);
    },
  );
  test('TXT checksum failure does not add a book', () async {
    textBooks = true;
    corrupt = true;
    await expectLater(
      catalog.install(CatalogItem.fromJson(itemJson('book'))),
      throwsA(isA<CatalogException>()),
    );
    expect(
      (await books.getBooks()).where((b) => b.id.startsWith('catalog_')),
      isEmpty,
    );
  });
  test(
    'downloads EPUB and cover into library, persists metadata and reuses one version',
    () async {
      final page = await catalog.list('book');
      final item = page.items.single;
      expect(await catalog.isInstalled(item), false);
      await catalog.install(item);
      await catalog.install(item);
      final book = (await books.getBooks()).singleWhere(
        (book) => book.id == item.bookId,
      );
      expect(await File(book.localPath!).readAsBytes(), files['epub']);
      expect(await File(book.coverPath!).readAsBytes(), files['cover']);
      expect(Book.fromJson(book.toJson())!.coverPath, book.coverPath);
      expect(await catalog.isInstalled(item), true);
    },
  );
  test(
    'checksum failure never registers incomplete book or leaves partial files',
    () async {
      corrupt = true;
      await expectLater(
        catalog.install(CatalogItem.fromJson(itemJson('book'))),
        throwsA(isA<CatalogException>()),
      );
      expect(
        (await books.getBooks()).where(
          (book) => book.id.startsWith('catalog_'),
        ),
        isEmpty,
      );
      expect(
        directory
            .listSync(recursive: true)
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
    },
  );
  test(
    'font updates are atomic and failed new version preserves installed manifest',
    () async {
      final item = CatalogItem.fromJson(itemJson('font'));
      await catalog.install(item);
      final manifest = File(
        '${directory.path}/cloud_reader/fonts/catalog.json',
      );
      final before = await manifest.readAsString();
      final json = jsonDecode(before) as Map<String, dynamic>;
      expect(json['families'][0]['id'], item.fontId);
      expect(json['families'][0]['faces'][0]['weight'], 400);
      expect(await catalog.isInstalled(item), true);
      final next = itemJson('font', version: 2);
      next['assets']['font400']['sha256'] = 'b' * 64;
      await expectLater(
        catalog.install(CatalogItem.fromJson(next)),
        throwsA(isA<CatalogException>()),
      );
      expect(await manifest.readAsString(), before);
    },
  );
  test(
    'new book revision has independent ID so old reading positions remain addressable',
    () async {
      await catalog.install(CatalogItem.fromJson(itemJson('book')));
      await catalog.install(CatalogItem.fromJson(itemJson('book', version: 2)));
      expect(
        (await books.getBooks())
            .where((book) => book.id.startsWith('catalog_'))
            .length,
        2,
      );
    },
  );
  test(
    'remote file paths, unexpected slots and invalid weights are rejected',
    () {
      final bad = itemJson('book');
      bad['assets']['epub']['extension'] = '../other';
      expect(() => CatalogItem.fromJson(bad), throwsFormatException);
      final badFont = itemJson('font');
      badFont['assets']['font400']['weight'] = 700;
      expect(() => CatalogItem.fromJson(badFont), throwsFormatException);
      final badId = itemJson('book');
      badId['id'] = '../escape';
      expect(() => CatalogItem.fromJson(badId), throwsFormatException);
      final ambiguous = itemJson('book');
      ambiguous['assets']['txt'] = asset('txt');
      expect(() => CatalogItem.fromJson(ambiguous), throwsFormatException);
      final noBody = itemJson('book');
      noBody['assets'].remove('epub');
      expect(() => CatalogItem.fromJson(noBody), throwsFormatException);
      final wrongSlot = itemJson('book');
      wrongSlot['assets']['epub'] = asset('txt');
      expect(() => CatalogItem.fromJson(wrongSlot), throwsFormatException);
    },
  );
}
