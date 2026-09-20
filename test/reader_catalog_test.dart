import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

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
  final files = {
    'epub': utf8.encode('epub test bytes'),
    'cover': utf8.encode('cover test bytes'),
    'font400': utf8.encode('OTTO verified test font'),
  };
  Map<String, dynamic> asset(String slot) => {
    'sha256': sha256.convert(files[slot]!).toString(),
    'size': files[slot]!.length,
    'extension': slot == 'font400'
        ? 'otf'
        : slot == 'cover'
        ? 'webp'
        : 'epub',
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
        ? {'epub': asset('epub'), 'cover': asset('cover')}
        : {'font400': asset('font400')},
  };
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('reader_catalog_test_');
    books = LocalBookRepository(MemoryStorage());
    corrupt = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/file') {
        final bytes = files[request.uri.queryParameters['slot']]!;
        request.response.add(corrupt ? List.filled(bytes.length, 0) : bytes);
      } else if (request.uri.queryParameters['action'] == 'download') {
        final slot = request.uri.queryParameters['slot']!;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            ...asset(slot),
            'url': 'http://127.0.0.1:${server.port}/file?slot=$slot',
          }),
        );
      } else {
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
    },
  );
}
