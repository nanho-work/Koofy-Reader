import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/backup/data/library_backup.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';

class MemoryBackupStorage implements LocalStorage {
  final strings = <String, String>{};
  final ints = <String, int>{};
  String? failOnce;
  @override
  Future<String?> getString(String key) async => strings[key];
  @override
  Future<void> setString(String key, String value) async {
    if (failOnce == key) {
      failOnce = null;
      throw const FileSystemException('disk full');
    }
    strings[key] = value;
  }

  @override
  Future<int?> getInt(String key) async => ints[key];
  @override
  Future<void> setInt(String key, int value) async {
    ints[key] = value;
  }

  @override
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix) async => {
    for (final entry in strings.entries)
      if (entry.key.startsWith(prefix)) entry.key: entry.value,
  };
}

class BackupFixture {
  BackupFixture(this.root) {
    covers = BookCoverStore(
      storage,
      directory: () async => Directory('${root.path}/book_covers'),
    );
    books = LocalBookRepository(storage, covers: covers);
    groups = BookGroupRepository(storage);
    preparer = ReadingPublicationPreparer(
      storageDirectory: Directory('${root.path}/publications'),
    );
    service = LibraryBackupService(
      storage: storage,
      books: books,
      groups: groups,
      covers: covers,
      reader: reader,
      preparer: preparer,
      directory: Directory('${root.path}/library_backups'),
    );
  }
  final Directory root;
  final storage = MemoryBackupStorage();
  final reader = NativeReaderStore(NativeDatabase.memory());
  late final BookCoverStore covers;
  late final LocalBookRepository books;
  late final BookGroupRepository groups;
  late final ReadingPublicationPreparer preparer;
  late final LibraryBackupService service;
  Future<void> dispose() async {
    await reader.close();
    await root.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BackupFixture source;
  late BackupFixture target;
  late String bookId;
  late String revision;
  setUp(() async {
    source = BackupFixture(
      await Directory.systemTemp.createTemp('koofy-source-'),
    );
    target = BackupFixture(
      await Directory.systemTemp.createTemp('koofy-target-'),
    );
    final first = await File(
      '${source.root.path}/1화.txt',
    ).writeAsString('[장] 제1화\n가나다라 소설의 첫 부분');
    final second = await File(
      '${source.root.path}/2화.txt',
    ).writeAsString('[장] 제2화\n다음 이야기');
    final a = (await source.books.importBookFile(first.path))!;
    final b = (await source.books.importBookFile(second.path))!;
    bookId = a.id;
    final publication = await source.preparer.prepare(book: a);
    revision = publication.contentRevision;
    final session = await source.reader.beginSession(a.id, revision);
    await source.reader.acceptCheckpoint(
      ReaderEvent(
        protocolVersion: 1,
        sessionId: session.id,
        sessionGeneration: session.generation,
        publicationId: a.id,
        contentRevision: revision,
        sequence: 1,
        kind: 'closed',
        bookmarksJson:
            '[{"id":"bookmark-1","label":"다시 읽을 문장","locator":{"href":"chapter.xhtml","type":"application/xhtml+xml"}}]',
        locatorJson: '{"href":"chapter.xhtml","locations":{"progression":0.5}}',
        preferences: defaultReaderPreferences()
          ..theme = 'sepia'
          ..fontScale = 1.4,
      ),
    );
    await source.groups.create('소설 묶음', [b.id, a.id]);
    await source.groups.setMemberCovers(
      (await source.groups.load()).single.id,
      true,
    );
    await LibraryCompletionRepository(source.storage).setFinished(a.id, true);
    await source.storage.setInt(AppConstants.adHideExpiryKey, 9999999999999);
    await source.storage.setString('reader_privacy_consent', 'private');
    final coverDir = Directory('${source.root.path}/book_covers');
    await coverDir.create();
    const name = '0123456789abcdef0123456789abcdef.png';
    await File('${coverDir.path}/$name').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
    );
    for (final id in [a.id, (await source.groups.load()).single.id]) {
      await source.storage.setString(
        'library_cover_${base64Url.encode(utf8.encode(id))}',
        name,
      );
    }
    // Reading retained an app-owned original: expired picker paths remain portable.
    await first.delete();
  });
  tearDown(() async {
    await source.dispose();
    await target.dispose();
  });

  test(
    'round trip restores source bytes, covers, group order, settings and exact locator',
    () async {
      final backup = LibraryBackupService.decode(await source.service.export());
      expect(
        backup.manifest.toString(),
        isNot(contains('reader_privacy_consent')),
      );
      expect(await target.service.restore(backup), 2);
      final book = (await target.books.getBooks()).firstWhere(
        (b) => b.id == bookId,
      );
      expect(await File(book.localPath!).readAsString(), contains('가나다라'));
      expect(await File(book.coverPath!).exists(), isTrue);
      expect(
        (await target.preparer.prepare(book: book)).contentRevision,
        revision,
      );
      final position = await target.reader.loadPosition(bookId, revision);
      expect(position.locatorJson, contains('"progression":0.5'));
      expect(position.bookmarksJson, contains('다시 읽을 문장'));
      expect(position.preferences.theme, 'sepia');
      expect(position.preferences.fontScale, 1.4);
      final group = (await target.groups.load()).single;
      expect(group.bookIds, (await source.groups.load()).single.bookIds);
      expect(group.showMemberCovers, isTrue);
      expect(
        (await target.covers.apply([group.displayBook])).single.coverPath,
        isNotNull,
      );
      expect(
        (await LibraryCompletionRepository(target.storage).load())[bookId],
        isTrue,
      );
      expect(await target.storage.getInt(AppConstants.adHideExpiryKey), isNull);
      expect(await target.service.restore(backup), 0);
      expect(await target.groups.load(), hasLength(1));
    },
  );

  test('restore preserves newer local progress and appearance', () async {
    final backup = LibraryBackupService.decode(await source.service.export());
    await target.service.restore(backup);
    final session = await target.reader.beginSession(bookId, revision);
    await target.reader.acceptCheckpoint(
      ReaderEvent(
        protocolVersion: 1,
        sessionId: session.id,
        sessionGeneration: session.generation,
        publicationId: bookId,
        contentRevision: revision,
        sequence: 1,
        kind: 'closed',
        locatorJson: '{"href":"new.xhtml"}',
        preferences: defaultReaderPreferences()..theme = 'dark',
      ),
    );
    await target.service.restore(backup);
    final position = await target.reader.loadPosition(bookId, revision);
    expect(position.locatorJson, contains('new.xhtml'));
    expect(position.preferences.theme, 'dark');
  });

  test('failed metadata commit rolls back library and database', () async {
    final backup = LibraryBackupService.decode(await source.service.export());
    target.storage.failOnce = BookGroupRepository.storageKey;
    await expectLater(
      target.service.restore(backup),
      throwsA(isA<FileSystemException>()),
    );
    expect(
      (await target.books.getBooks()).where((b) => b.isLocalFile),
      isEmpty,
    );
    expect(await target.reader.loadLibraryPositions(), isEmpty);
    expect(await target.groups.load(), isEmpty);
    expect(await target.service.restore(backup), 2);
  });

  test(
    'unsafe archive paths and changed payloads are rejected before restore',
    () async {
      final unsafe = Archive()..addFile(ArchiveFile('../outside.txt', 1, [1]));
      expect(
        () => LibraryBackupService.decode(
          Uint8List.fromList(ZipEncoder().encode(unsafe)),
        ),
        throwsFormatException,
      );
      final archive = ZipDecoder().decodeBytes(await source.service.export());
      final changed = Archive();
      var edited = false;
      for (final file in archive.files) {
        if (!edited && file.name.endsWith('.txt')) {
          changed.addFile(ArchiveFile(file.name, 1, [1]));
          edited = true;
        } else {
          changed.addFile(file);
        }
      }
      expect(
        () => LibraryBackupService.decode(
          Uint8List.fromList(ZipEncoder().encode(changed)),
        ),
        throwsFormatException,
      );
      expect(
        (await target.books.getBooks()).where((b) => b.isLocalFile),
        isEmpty,
      );
    },
  );
}
