import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';

import 'native_reader_store_test.dart' show checkpoint;

const bookmarks =
    '[{"id":"one","label":"다시 읽기","locator":{"href":"chapter.xhtml","type":"application/xhtml+xml","locations":{"progression":0.4}}}]';

void main() {
  test(
    'bookmarks survive bridge, ordinary events, stale replay and deletion',
    () async {
      final store = NativeReaderStore(NativeDatabase.memory());
      addTearDown(store.close);
      final session = await store.beginSession('book', 'r1');
      final event = ReaderEvent.decode(
        (checkpoint(session)..bookmarksJson = bookmarks).encode(),
      );
      await store.acceptCheckpoint(event);
      await store.acceptCheckpoint(checkpoint(session, sequence: 2));
      expect((await store.loadPosition('book', 'r1')).bookmarksJson, bookmarks);
      expect((await store.loadPosition('book', 'r2')).bookmarksJson, '[]');
      expect((await store.loadPosition('other', 'r1')).bookmarksJson, '[]');
      await store.acceptCheckpoint(
        checkpoint(session, sequence: 3)..bookmarksJson = '[]',
      );
      await store.acceptCheckpoint(event);
      expect((await store.loadPosition('book', 'r1')).bookmarksJson, '[]');
      final next = await store.beginSession('book', 'r1');
      await store.acceptCheckpoint(checkpoint(next)..bookmarksJson = bookmarks);
      await store.acceptCheckpoint(
        checkpoint(session, sequence: 999)..bookmarksJson = '[]',
      );
      expect((await store.loadPosition('book', 'r1')).bookmarksJson, bookmarks);
    },
  );

  test(
    'invalid bookmark snapshots roll back position and settings atomically',
    () async {
      final store = NativeReaderStore(NativeDatabase.memory());
      addTearDown(store.close);
      final session = await store.beginSession('book', 'r1');
      await store.acceptCheckpoint(
        checkpoint(session)..bookmarksJson = bookmarks,
      );
      for (final invalid in [
        '{}',
        '[{"id":"broken"}]',
        jsonEncode([...jsonDecode(bookmarks), ...jsonDecode(bookmarks)]),
        jsonEncode(List.filled(101, jsonDecode(bookmarks)[0])),
      ]) {
        await expectLater(
          store.acceptCheckpoint(
            checkpoint(session, sequence: 2, href: 'wrong.xhtml')
              ..bookmarksJson = invalid
              ..preferences!.theme = 'dark',
          ),
          throwsFormatException,
        );
        final saved = await store.loadPosition('book', 'r1');
        expect(saved.bookmarksJson, bookmarks);
        expect(saved.locatorJson, contains('chapter.xhtml'));
        expect(saved.preferences.theme, 'light');
      }
    },
  );

  test(
    'v3 upgrade preserves positions and persisted bookmarks survive reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'koofy-bookmarks-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/reader.sqlite');
      final old = NativeReaderStore(NativeDatabase(file));
      final session = await old.beginSession('book', 'r1');
      await old.acceptCheckpoint(checkpoint(session));
      // Recreate the previous schema, which had no bookmark column.
      await old.customStatement(
        'ALTER TABLE reader_positions DROP COLUMN bookmarks_json',
      );
      await old.customStatement('PRAGMA user_version=3');
      await old.close();
      final upgraded = NativeReaderStore(NativeDatabase(file));
      expect((await upgraded.loadPosition('book', 'r1')).bookmarksJson, '[]');
      expect(
        (await upgraded.loadPosition('book', 'r1')).locatorJson,
        contains('chapter.xhtml'),
      );
      await upgraded.acceptCheckpoint(
        checkpoint(session, sequence: 2)..bookmarksJson = bookmarks,
      );
      await upgraded.close();
      final reopened = NativeReaderStore(NativeDatabase(file));
      addTearDown(reopened.close);
      expect(
        (await reopened.loadPosition('book', 'r1')).bookmarksJson,
        bookmarks,
      );
      final backup = await reopened.exportBackup({'book'});
      final target = NativeReaderStore(NativeDatabase.memory());
      addTearDown(target.close);
      await target.mergeBackup(backup, {'book'}, () async {});
      expect(
        (await target.loadPosition('book', 'r1')).bookmarksJson,
        bookmarks,
      );
    },
  );

  test('backups made before bookmarks restore with an empty list', () async {
    final store = NativeReaderStore(NativeDatabase.memory());
    addTearDown(store.close);
    await store.mergeBackup(
      {
        'preferences': preferencesToJson(defaultReaderPreferences()),
        'positions': [
          {
            'bookId': 'book',
            'revision': 'r1',
            'locator': '{"href":"chapter.xhtml"}',
            'openedAt': null,
          },
        ],
      },
      {'book'},
      () async {},
    );
    expect((await store.loadPosition('book', 'r1')).bookmarksJson, '[]');
  });
}
