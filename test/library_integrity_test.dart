import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/backup/data/library_backup.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'library_backup_test.dart' show BackupFixture, MemoryBackupStorage;

class PausedStorage extends MemoryBackupStorage {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool first = true;
  @override
  Future<String?> getString(String key) async {
    final snapshot = strings[key];
    if (first && key == AppConstants.localBooksKey) {
      first = false;
      entered.complete();
      await release.future;
    }
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BackupFixture source;
  late BackupFixture target;
  setUp(() async {
    source = BackupFixture(
      await Directory.systemTemp.createTemp('integrity-source-'),
    );
    target = BackupFixture(
      await Directory.systemTemp.createTemp('integrity-target-'),
    );
  });
  tearDown(() async {
    await source.dispose();
    await target.dispose();
  });

  Future<Book> add(String name) async => (await source.books.importBookFile(
    (await File(
      '${source.root.path}/$name.txt',
    ).writeAsString('본문 $name')).path,
  ))!;

  test('unread imports survive original expiry and can be backed up', () async {
    final a = await add('one');
    await File('${source.root.path}/one.txt').delete();
    expect(await File(a.localPath!).readAsString(), '본문 one');
    expect((await source.preparer.prepare(book: a)).publicationId, a.id);
    expect(
      LibraryBackupService.decode(await source.service.export()).bookCount,
      3,
    );
  });

  test(
    'import and download across repositories cannot lose an update',
    () async {
      final storage = PausedStorage();
      LocalBookRepository repo() => LocalBookRepository(
        storage,
        sourceDirectory: () async => Directory('${source.root.path}/owned'),
      );
      final a = await File('${source.root.path}/one.txt').writeAsString('one');
      final b = await File('${source.root.path}/two.txt').writeAsString('two');
      final first = repo().importBookFile(a.path);
      await storage.entered.future;
      final second = repo().saveDownloadedBook(
        Book.localFile(
          id: 'download',
          title: 'two',
          author: '',
          description: '',
          localPath: b.path,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      storage.release.complete();
      await Future.wait([first, second]);
      expect(
        (await repo().getBooks()).where((b) => b.isLocalFile),
        hasLength(2),
      );
    },
  );

  test(
    'corrupt library blocks mutations and preserves both raw copies',
    () async {
      source.storage.strings[AppConstants.localBooksKey] = 'broken primary';
      source.storage.strings[AppConstants.localBooksBackupKey] =
          'broken backup';
      await expectLater(add('new'), throwsFormatException);
      expect(
        source.storage.strings[AppConstants.localBooksKey],
        'broken primary',
      );
      expect(
        source.storage.strings[AppConstants.localBooksBackupKey],
        'broken backup',
      );
    },
  );

  test(
    'a malformed row cannot silently disappear during a later import',
    () async {
      source.storage.strings[AppConstants.localBooksKey] = '[{"id":"broken"}]';
      await expectLater(add('new'), throwsFormatException);
      expect(
        source.storage.strings[AppConstants.localBooksKey],
        '[{"id":"broken"}]',
      );
    },
  );

  Future<({String id, String group, LibraryBackup backup})>
  backupWithSharedCover() async {
    final a = await add('one');
    final b = await add('two');
    await source.groups.create('묶음', [a.id, b.id]);
    final group = (await source.groups.load()).single.id;
    await LibraryCompletionRepository(source.storage).setFinished(a.id, true);
    final dir = await Directory('${source.root.path}/book_covers').create();
    const name = '0123456789abcdef0123456789abcdef.png';
    await File('${dir.path}/$name').writeAsBytes(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
    );
    for (final id in [a.id, group]) {
      source
              .storage
              .strings['library_cover_${base64Url.encode(utf8.encode(id))}'] =
          name;
    }
    return (
      id: a.id,
      group: group,
      backup: LibraryBackupService.decode(await source.service.export()),
    );
  }

  test(
    'restore retry after a late write failure restores covers and completion',
    () async {
      final f = await backupWithSharedCover();
      target.storage.failOnce = AppConstants.hiddenBooksKey;
      await expectLater(
        target.service.restore(f.backup),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        target.storage.strings.keys.where(
          (k) => k.startsWith('library_cover_'),
        ),
        isEmpty,
      );
      await target.service.restore(f.backup);
      expect(
        (await LibraryCompletionRepository(target.storage).load())[f.id],
        true,
      );
      final book = (await target.books.getBooks()).firstWhere(
        (b) => b.id == f.id,
      );
      expect(await File(book.coverPath!).exists(), true);
      expect(
        (await target.groups.load()).single.bookIds,
        (await source.groups.load()).single.bookIds,
      );
    },
  );

  test('restored identical covers have separate ownership', () async {
    final f = await backupWithSharedCover();
    await target.service.restore(f.backup);
    final group = (await target.groups.load()).single;
    final display = (await target.covers.apply([group.displayBook])).single;
    await target.covers.reset(f.id);
    expect(await File(display.coverPath!).exists(), true);
  });

  test(
    'old shared cover is preserved until its last reference is removed',
    () async {
      final f = await backupWithSharedCover();
      final group = (await source.groups.load()).single;
      final display = (await source.covers.apply([group.displayBook])).single;
      await source.covers.reset(f.id);
      expect(await File(display.coverPath!).exists(), true);
      await source.covers.reset(f.group);
      expect(await File(display.coverPath!).exists(), false);
    },
  );

  test(
    'persisted settings use the same font scale range as native readers',
    () {
      expect(
        () => preferencesToJson(defaultReaderPreferences()..fontScale = 3.5),
        throwsFormatException,
      );
      expect(
        preferencesFromJson(
          preferencesToJson(defaultReaderPreferences()..fontScale = 3),
        ).fontScale,
        3,
      );
    },
  );
}
