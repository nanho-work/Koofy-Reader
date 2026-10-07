import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/library_trash_store.dart';
import 'package:koofy_reader/features/library/data/library_trash_service.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'reader_catalog_test.dart' show MemoryStorage;

void main() {
  late Directory root;
  late MemoryStorage storage;
  late LibraryTrashStore trash;
  late LocalBookRepository books;
  late BookGroupRepository groups;
  late LibraryTrashService service;
  var failRecords = false;
  final deleted = <String>{};
  setUp(() async {
    root = await Directory.systemTemp.createTemp('trash_test_');
    storage = MemoryStorage();
    trash = LibraryTrashStore(storage);
    books = LocalBookRepository(storage);
    groups = BookGroupRepository(storage);
    failRecords = false;
    deleted.clear();
    service = LibraryTrashService(
      storage,
      root,
      deleteReadingRecords: (ids) async {
        if (failRecords) throw StateError('simulated disk error');
        deleted.addAll(ids);
      },
    );
  });
  tearDown(() async => root.delete(recursive: true));
  Future<File> file(String name, [String text = 'body']) async {
    final file = File('${root.path}/$name');
    await file.parent.create(recursive: true);
    return file.writeAsString(text);
  }

  Future<Book> book(String id, String path, {String? cover}) async {
    final value = Book.localFile(
      id: id,
      title: id,
      author: 'author',
      description: '',
      localPath: path,
      coverPath: cover,
    );
    await books.saveDownloadedBook(value);
    return value;
  }

  String coverKey(String id) =>
      'library_cover_${base64Url.encode(utf8.encode(id))}';

  test(
    'batch trash and restore preserves original group order and cover preference',
    () async {
      final a = await book('a', (await file('library_sources/a.txt')).path);
      final b = await book('b', (await file('library_sources/b.txt')).path);
      await groups.create('novel', [b.id, a.id]);
      final group = (await groups.load()).single;
      await storage.setString(coverKey(group.id), '${'c' * 32}.png');
      await groups.trashGroup(group.id, keepShelf: false);
      expect(await groups.load(), isEmpty);
      expect(await trash.hiddenBookIds(), {'a', 'b'});
      expect((await trash.load()).length, 1);
      await groups.restoreBundle((await trash.load()).keys.single);
      expect((await groups.load()).single.bookIds, ['b', 'a']);
      expect(await storage.getString(coverKey(group.id)), '${'c' * 32}.png');
      expect(await trash.load(), isEmpty);
      expect(await File(a.localPath!).exists(), true);
    },
  );

  test(
    'empty shelf retains group and restore respects a newly assigned membership',
    () async {
      await book('a', (await file('library_sources/a.txt')).path);
      await book('b', (await file('library_sources/b.txt')).path);
      await book('c', (await file('library_sources/c.txt')).path);
      await groups.create('first', ['a', 'b']);
      final id = (await groups.load()).single.id;
      await groups.trashGroup(id, keepShelf: true);
      expect((await groups.load()).single.bookIds, isEmpty);
      final entry = (await trash.load()).keys.single;
      await trash.restoreBook('a');
      await groups.create('second', ['a', 'c']);
      await groups.restoreBundle(entry);
      expect((await groups.load()).first.bookIds, ['b']);
      expect((await groups.load()).last.bookIds, ['a', 'c']);
      expect(await trash.hiddenBookIds(), isEmpty);
    },
  );

  test(
    'purge frees owned content, cover and prepared bytes but preserves original external file',
    () async {
      final source = await file('library_sources/book/source.txt');
      final external = await file('originals/source.txt');
      final cover = await file('book_covers/${'c' * 32}.png');
      final a = await book('a', source.path);
      await storage.setString(coverKey('a'), '${'c' * 32}.png');
      final hash = 'd' * 64;
      final reference = await file(
        'native_reader_v1/publications/references/${sha256.convert(utf8.encode('a'))}.json',
        jsonEncode({'sourceHash': hash}),
      );
      final prepared = await file(
        'native_reader_v1/publications/$hash/body.epub',
      );
      await storage.setString(
        '${AppConstants.readingProgressPrefix}a',
        'position',
      );
      await trash.moveBook(a);
      expect(
        await service.bytes({'a'}),
        await source.length() +
            await cover.length() +
            await reference.length() +
            await prepared.length(),
      );
      await service.purge('a');
      for (final file in [source, cover, reference, prepared]) {
        expect(await file.exists(), false);
      }
      expect(await external.exists(), true);
      expect(deleted, {'a'});
      expect(
        await storage.getString('${AppConstants.readingProgressPrefix}a'),
        isNull,
      );
      expect((await books.allStoredBooks()).any((b) => b.id == 'a'), false);
      expect(await trash.load(), isEmpty);
    },
  );

  test(
    'shared source and cover survive first purge and disappear after final owner',
    () async {
      final source = await file('cloud_reader/books/shared.txt');
      final cover = await file('cloud_reader/books/shared.webp');
      final a = await book('a', source.path, cover: cover.path),
          b = await book('b', source.path, cover: cover.path);
      await trash.moveBook(a);
      await trash.moveBook(b);
      expect(await service.bytes({'a'}), 0);
      expect(
        await service.bytes({'a', 'b'}),
        await source.length() + await cover.length(),
      );
      await service.purge('a');
      expect(await source.exists(), true);
      expect(await cover.exists(), true);
      await service.purge('b');
      expect(await source.exists(), false);
      expect(await cover.exists(), false);
    },
  );

  test(
    'deletion failure remains pending, cannot be restored and can be retried',
    () async {
      final source = await file('library_sources/book/source.txt');
      final a = await book('a', source.path);
      await trash.moveBook(a);
      failRecords = true;
      await expectLater(service.purge('a'), throwsStateError);
      expect((await trash.load())['a']!['deleting'], true);
      await expectLater(trash.restoreBook('a'), throwsStateError);
      failRecords = false;
      await service.purge('a');
      expect(await trash.load(), isEmpty);
      expect(
        (await books.allStoredBooks()).any((book) => book.id == 'a'),
        false,
      );
    },
  );

  test(
    'external paths and links outside owned directories are never removed',
    () async {
      final external = await file('originals/a.txt');
      final link = Link('${root.path}/library_sources/link.txt');
      await link.parent.create(recursive: true);
      await link.create(external.path);
      final a = await book('a', external.path), b = await book('b', link.path);
      await trash.moveBook(a);
      await trash.moveBook(b);
      await service.empty({'a', 'b'});
      expect(await external.exists(), true);
      expect(await link.exists(), true);
    },
  );

  test(
    'emptying a shelf and purging retains its cover and empty container',
    () async {
      await book('a', (await file('library_sources/a.txt')).path);
      await book('b', (await file('library_sources/b.txt')).path);
      await groups.create('first', ['a', 'b']);
      final id = (await groups.load()).single.id;
      final cover = await file('book_covers/${'e' * 32}.png');
      await storage.setString(coverKey(id), '${'e' * 32}.png');
      await groups.trashGroup(id, keepShelf: true);
      await service.empty((await trash.load()).keys.toSet());
      expect((await groups.load()).single.id, id);
      expect((await groups.load()).single.bookIds, isEmpty);
      expect(await cover.exists(), true);
      expect(deleted, {'a', 'b'});
    },
  );
  test(
    'pending cleanup retries a prepared file after its reference has already gone',
    () async {
      final source = await file('library_sources/a.txt');
      final a = await book('a', source.path);
      final prepared = await file(
        'native_reader_v1/publications/${'f' * 64}/body.epub',
      );
      await trash.moveBook(a);
      final data = await trash.load();
      data['a']!['deleting'] = true;
      data['a']!['purgePaths'] = [prepared.path, source.path];
      await trash.save(data);
      await service.purge('a');
      expect(await prepared.exists(), false);
      expect(await trash.load(), isEmpty);
    },
  );
}
