import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_trash_service.dart';
import 'package:koofy_reader/features/library/data/library_trash_store.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'reader_catalog_test.dart' show MemoryStorage;

class CountingTrashStorage extends MemoryStorage {
  final reads = <String, int>{}, writes = <String, int>{};
  int coverScans = 0;
  @override
  Future<String?> getString(String key) async {
    reads.update(key, (value) => value + 1, ifAbsent: () => 1);
    return super.getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    writes.update(key, (value) => value + 1, ifAbsent: () => 1);
    return super.setString(key, value);
  }

  @override
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix) {
    if (prefix == 'library_cover_') coverScans++;
    return super.getStringEntriesByPrefix(prefix);
  }
}

void main() {
  late Directory root;
  late CountingTrashStorage storage;
  late LibraryTrashStore trash;
  late LibraryTrashService service;
  final events = <TrashDeleteProgress?>[];
  final removed = <String>{};
  var failRecords = false;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bulk_trash_');
    storage = CountingTrashStorage();
    trash = LibraryTrashStore(storage);
    events.clear();
    removed.clear();
    failRecords = false;
    service = LibraryTrashService(
      storage,
      root,
      deleteReadingRecords: (ids) async {
        if (failRecords) throw StateError('disk error');
        removed.addAll(ids);
      },
      onProgress: events.add,
    );
  });
  tearDown(() async => root.delete(recursive: true));

  Future<List<Book>> seed(int count) async {
    final books = <Book>[];
    for (var i = 0; i < count; i++) {
      final source = File('${root.path}/library_sources/$i/source.txt');
      await source.parent.create(recursive: true);
      await source.writeAsString('book $i');
      books.add(
        Book.localFile(
          id: 'b$i',
          title: '$i',
          author: '',
          description: '',
          localPath: source.path,
        ),
      );
    }
    await storage.setString(
      AppConstants.localBooksKey,
      jsonEncode(books.map((b) => b.toJson()).toList()),
    );
    return books;
  }

  test(
    '400 books delete in batches without per-file library or cover scans',
    () async {
      final books = await seed(401);
      final data = <String, Map<String, dynamic>>{};
      for (final book in books.take(400)) {
        final hash = sha256.convert(utf8.encode(book.id)).toString();
        final reference = File(
          '${root.path}/native_reader_v1/publications/references/$hash.json',
        );
        await reference.parent.create(recursive: true);
        await reference.writeAsString(jsonEncode({'sourceHash': hash}));
        final prepared = File(
          '${root.path}/native_reader_v1/publications/$hash/body.epub',
        );
        await prepared.parent.create(recursive: true);
        await prepared.writeAsString('prepared');
        data[book.id] = {
          'title': book.title,
          'kind': 'book',
          'deletedAt': '2026-11-01',
        };
      }
      await trash.save(data);
      storage.reads.clear();
      storage.writes.clear();
      await service.empty(data.keys.toSet());
      expect(removed.length, 400);
      expect(await trash.load(), isEmpty);
      expect(await File(books.last.localPath!).exists(), isTrue);
      expect(
        (await LocalBookRepository(
          storage,
        ).allStoredBooks()).where((b) => b.isLocalFile).map((b) => b.id),
        ['b400'],
      );
      expect(storage.coverScans, 1);
      expect(storage.reads[AppConstants.localBooksKey], lessThan(80));
      expect(storage.writes[AppConstants.localBooksKey], lessThan(80));
      expect(
        events.whereType<TrashDeleteProgress>().last.completedEntries,
        400,
      );
      expect(events.last, isNull);
    },
  );

  test(
    '300 episode bundle reports file progress and keeps another book intact',
    () async {
      final books = await seed(301);
      final groups = BookGroupRepository(storage);
      await groups.create(
        '300 episodes',
        books.take(300).map((b) => b.id).toList(),
      );
      final group = (await groups.load()).single;
      await groups.trashGroup(group.id, keepShelf: false);
      await service.empty((await trash.load()).keys.toSet());
      expect(removed.length, 300);
      expect(await trash.load(), isEmpty);
      expect(await File(books.last.localPath!).exists(), isTrue);
      final files = events.whereType<TrashDeleteProgress>().where(
        (e) => e.stage == TrashDeleteStage.files,
      );
      expect(
        files.any(
          (e) => e.completedFiles > 0 && e.completedFiles < e.totalFiles,
        ),
        isTrue,
      );
      expect(
        events.whereType<TrashDeleteProgress>().any(
          (e) => e.stage == TrashDeleteStage.records,
        ),
        isTrue,
      );
    },
  );

  test(
    'failed batch remains pending and can retry individual entries after restart',
    () async {
      final books = await seed(18);
      for (final book in books) {
        await trash.moveBook(book);
      }
      failRecords = true;
      await expectLater(
        service.empty(books.map((b) => b.id).toSet()),
        throwsStateError,
      );
      final pending = await trash.load();
      expect(pending.values.where((e) => e['deleting'] == true).length, 16);
      await expectLater(trash.restoreBook('b0'), throwsStateError);
      expect(pending['b17']!['deleting'], isNot(true));
      await trash.restoreBook('b17');
      expect(await File(books.last.localPath!).exists(), isTrue);
      failRecords = false;
      await service.purge('b0');
      await service.empty((await trash.load()).keys.toSet());
      expect(await trash.load(), isEmpty);
      expect(removed.length, 17);
      expect(events.last, isNull);
    },
  );

  test(
    'shared file across batch boundaries is preserved until final owner',
    () async {
      final books = await seed(18);
      final shared = books.first.localPath!;
      final linked = books
          .map(
            (book) => book.id == 'b16' || book.id == 'b17'
                ? Book.localFile(
                    id: book.id,
                    title: book.title,
                    author: '',
                    description: '',
                    localPath: shared,
                  )
                : book,
          )
          .toList();
      await storage.setString(
        AppConstants.localBooksKey,
        jsonEncode(linked.map((b) => b.toJson()).toList()),
      );
      for (final book in linked.take(17)) {
        await trash.moveBook(book);
      }
      await service.empty((await trash.load()).keys.toSet());
      expect(await File(shared).exists(), isTrue);
      await trash.moveBook(linked.last);
      await service.purge(linked.last.id);
      expect(await File(shared).exists(), isFalse);
    },
  );

  test('a second deletion cannot queue behind an active deletion', () async {
    final books = await seed(1);
    await trash.moveBook(books.single);
    final gate = Completer<void>();
    final active = LibraryTrashService(
      storage,
      root,
      beforeDelete: () => gate.future,
      deleteReadingRecords: (_) async {},
      onProgress: events.add,
    );
    final work = active.empty({'b0'});
    await expectLater(active.purge('b0'), throwsStateError);
    gate.complete();
    await work;
    expect(await trash.load(), isEmpty);
    expect(events.last, isNull);
  });
}
