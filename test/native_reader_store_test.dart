import 'dart:io';

import 'package:drift/drift.dart' show MigrationStrategy;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';

ReaderEvent checkpoint(
  ReaderSessionIdentity session, {
  int sequence = 1,
  String revision = 'r1',
  String href = 'chapter.xhtml',
}) => ReaderEvent(
  protocolVersion: 1,
  sessionId: session.id,
  sessionGeneration: session.generation,
  publicationId: 'book',
  contentRevision: revision,
  sequence: sequence,
  kind: 'locationChanged',
  locatorJson:
      '{"href":"$href","type":"application/xhtml+xml","locations":{"progression":0.4}}',
  preferences: defaultReaderPreferences(),
);

void main() {
  test('spacing survives native codec and can reset to publisher defaults', () {
    final preferences = defaultReaderPreferences()
      ..lineHeight = 1.8
      ..paragraphSpacing = 0.5
      ..pageMargins = 1.5;
    final decoded = ReaderPreferences.decode(preferences.encode());
    final restored = preferencesFromJson(preferencesToJson(decoded));
    expect(restored.lineHeight, 1.8);
    expect(restored.paragraphSpacing, 0.5);
    expect(restored.pageMargins, 1.5);
    restored.lineHeight = restored.paragraphSpacing = restored.pageMargins =
        null;
    final reset = preferencesFromJson(preferencesToJson(restored));
    expect(reset.lineHeight, isNull);
    expect(reset.paragraphSpacing, isNull);
    expect(reset.pageMargins, isNull);
  });

  test(
    'invalid spacing cannot overwrite the saved location or appearance',
    () async {
      final store = NativeReaderStore(NativeDatabase.memory());
      addTearDown(store.close);
      final session = await store.beginSession('book', 'r1');
      await store.acceptCheckpoint(checkpoint(session));
      for (final invalid in [
        defaultReaderPreferences()..lineHeight = double.nan,
        defaultReaderPreferences()..lineHeight = 0.9,
        defaultReaderPreferences()..paragraphSpacing = -1,
        defaultReaderPreferences()..pageMargins = 3,
      ]) {
        await expectLater(
          store.acceptCheckpoint(
            checkpoint(session, sequence: 2, href: 'wrong.xhtml')
              ..preferences = invalid,
          ),
          throwsFormatException,
        );
        final saved = await store.loadPosition('book', 'r1');
        expect(saved.locatorJson, contains('chapter.xhtml'));
        expect(saved.preferences.lineHeight, isNull);
        expect(saved.preferences.paragraphSpacing, isNull);
        expect(saved.preferences.pageMargins, isNull);
      }
    },
  );

  test(
    'legacy preference JSON defaults to instant without changing layout',
    () {
      final preferences = preferencesFromJson(
        '{"fontScale":1.4,"columnCount":2,"scroll":false,"theme":"sepia"}',
      );
      expect(preferences.pageTurnStyle, 'instant');
      expect(preferences.fontId, 'default');
      expect(preferences.fontScale, 1.4);
      expect(preferences.columnCount, 2);
      expect(preferences.theme, 'sepia');
      expect(preferences.lineHeight, isNull);
      expect(preferences.paragraphSpacing, isNull);
      expect(preferences.pageMargins, isNull);
    },
  );

  test('curl preference survives JSON and the generated bridge codec', () {
    final preferences = ReaderPreferences(
      fontScale: 1.2,
      columnCount: 2,
      scroll: true,
      theme: 'dark',
      pageTurnStyle: 'curl',
    );
    final decoded = ReaderPreferences.decode(preferences.encode());
    final restored = preferencesFromJson(preferencesToJson(decoded));
    expect(restored.pageTurnStyle, 'curl');
    expect(
      restored.scroll,
      isTrue,
    ); // Scrolling suspends, not erases, the choice.
    expect(restored.fontScale, 1.2);
  });

  test('font families survive the bridge codec and JSON round trip', () {
    for (final id in ['default', 'maplestory', 'hakgyoansim-siganpyo']) {
      final preferences = defaultReaderPreferences()..fontId = id;
      final decoded = ReaderPreferences.decode(preferences.encode());
      expect(preferencesFromJson(preferencesToJson(decoded)).fontId, id);
    }
    expect(
      () =>
          preferencesToJson(defaultReaderPreferences()..fontId = '../font.otf'),
      throwsFormatException,
    );
  });

  test(
    'v1 database upgrades without rewriting positions or inventing read dates',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'koofy-v1-upgrade-',
      );
      final file = File('${directory.path}/reader.sqlite');
      final old = _V1ReaderStore(NativeDatabase(file));
      await old.customStatement('INSERT INTO reader_counter VALUES (1, 1)');
      await old.customStatement(
        "INSERT INTO reader_sessions VALUES ('old', 1, 'book', 'r1')",
      );
      await old.customStatement(
        'INSERT INTO reader_positions VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'book',
          'r1',
          'old',
          1,
          4,
          '{"href":"saved.xhtml"}',
          '{"fontScale":1.0,"columnCount":0,"scroll":false,"theme":"light"}',
        ],
      );
      await old.close();
      final upgraded = NativeReaderStore(NativeDatabase(file));
      try {
        expect(
          (await upgraded.loadPosition('book', 'r1')).locatorJson,
          contains('saved.xhtml'),
        );
        expect(
          (await upgraded.loadPosition('book', 'r1')).preferences.pageTurnStyle,
          'instant',
        );
        final summary = (await upgraded.loadLibraryPositions()).single;
        expect(summary.lastOpenedAt, isNull);
        final session = await upgraded.beginSession('book', 'r1');
        expect(session.generation, 2);
        await upgraded.acceptCheckpoint(checkpoint(session));
        expect(
          (await upgraded.loadLibraryPositions()).single.lastOpenedAt,
          isNotNull,
        );
      } finally {
        await upgraded.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'v2 upgrade adopts latest book settings without replacing any locator',
    () async {
      final directory = await Directory.systemTemp.createTemp('koofy-v2-');
      final file = File('${directory.path}/reader.sqlite');
      final old = _V1ReaderStore(NativeDatabase(file));
      await old.customStatement(
        'ALTER TABLE reader_sessions ADD COLUMN started_at INTEGER',
      );
      await old.customStatement('INSERT INTO reader_counter VALUES (1, 2)');
      for (var i = 1; i <= 2; i++) {
        await old.customStatement(
          'INSERT INTO reader_sessions VALUES (?, ?, ?, ?, ?)',
          ['s$i', i, 'book$i', 'r1', i * 1000],
        );
        await old.customStatement(
          'INSERT INTO reader_positions VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            'book$i',
            'r1',
            's$i',
            i,
            4,
            '{"href":"book$i.xhtml"}',
            preferencesToJson(
              defaultReaderPreferences()..fontScale = i.toDouble(),
            ),
          ],
        );
      }
      await old.customStatement('PRAGMA user_version=2');
      await old.close();
      final upgraded = NativeReaderStore(NativeDatabase(file));
      try {
        for (final id in ['book1', 'book2', 'new']) {
          final position = await upgraded.loadPosition(id, 'r1');
          expect(position.preferences.fontScale, 2);
          expect(
            position.locatorJson,
            id == 'new' ? isNull : contains('$id.xhtml'),
          );
        }
        expect(await upgraded.loadLibraryPositions(), hasLength(2));
      } finally {
        await upgraded.close();
        await directory.delete(recursive: true);
      }
    },
  );

  group('checkpoint commits', () {
    late NativeReaderStore store;
    setUp(() => store = NativeReaderStore(NativeDatabase.memory()));
    tearDown(() => store.close());

    test('appearance is global while locations remain book-specific', () async {
      final first = await store.beginSession('book', 'r1');
      final custom = defaultReaderPreferences()
        ..fontScale = 1.5
        ..fontId = 'maplestory'
        ..theme = 'dark'
        ..scroll = true
        ..columnCount = 2
        ..pageTurnStyle = 'curl'
        ..lineHeight = 1.8
        ..paragraphSpacing = 0.5
        ..pageMargins = 1.5;
      await store.acceptCheckpoint(checkpoint(first)..preferences = custom);
      final other = await store.loadPosition('other', 'r1');
      expect(other.locatorJson, isNull);
      expect(preferencesToJson(other.preferences), preferencesToJson(custom));
      final next = await store.beginSession('other', 'r1');
      await store.acceptCheckpoint(
        checkpoint(next, href: 'other.xhtml')
          ..publicationId = 'other'
          ..preferences = (custom..theme = 'sepia'),
      );
      expect(
        (await store.loadPosition('book', 'r1')).locatorJson,
        contains('chapter.xhtml'),
      );
      expect(
        (await store.loadPosition('book', 'r1')).preferences.theme,
        'sepia',
      );
      expect(
        (await store.loadPosition('book', 'r2')).preferences.theme,
        'sepia',
      );
      await store.acceptCheckpoint(
        checkpoint(first, sequence: 99, href: 'late.xhtml'),
      );
      expect(
        (await store.loadPosition('book', 'r1')).preferences.theme,
        'sepia',
      );
      expect(
        (await store.loadPosition('other', 'r1')).locatorJson,
        contains('other.xhtml'),
      );
    });

    test(
      'library summary chooses newest committed revision and excludes failed opens',
      () async {
        final first = await store.beginSession('book', 'r1');
        await store.acceptCheckpoint(checkpoint(first));
        final second = await store.beginSession('book', 'r2');
        await store.acceptCheckpoint(
          checkpoint(second, revision: 'r2', href: 'second.xhtml'),
        );
        await store.beginSession('book', 'r3');
        await store.beginSession('failed-book', 'r1');
        final summaries = await store.loadLibraryPositions();
        expect(summaries, hasLength(1));
        expect(summaries.single.locatorJson, contains('second.xhtml'));
      },
    );

    test(
      'late recovery uses original session time, not receipt time',
      () async {
        final session = await store.beginSession('book', 'r1');
        await store.customStatement(
          'UPDATE reader_sessions SET started_at=1234 WHERE session_id=?',
          [session.id],
        );
        await store.acceptCheckpoint(checkpoint(session));
        final first = (await store.loadLibraryPositions()).single;
        expect(first.lastOpenedAt!.millisecondsSinceEpoch, 1234);
        await store.acceptCheckpoint(checkpoint(session, sequence: 2));
        expect(
          (await store.loadLibraryPositions()).single.lastOpenedAt,
          first.lastOpenedAt,
        );
      },
    );

    test(
      'duplicate and delayed locations cannot replace a newer committed location',
      () async {
        final session = await store.beginSession('book', 'r1');
        await store.acceptCheckpoint(
          checkpoint(session, sequence: 2, href: 'new.xhtml'),
        );
        await store.acceptCheckpoint(
          checkpoint(session, sequence: 1, href: 'old.xhtml'),
        );
        await store.acceptCheckpoint(
          checkpoint(session, sequence: 2, href: 'duplicate.xhtml'),
        );
        expect(
          (await store.loadPosition('book', 'r1')).locatorJson,
          contains('new.xhtml'),
        );
      },
    );

    test(
      'a new session invalidates older location events even before first new event',
      () async {
        final oldSession = await store.beginSession('book', 'r1');
        await store.acceptCheckpoint(
          checkpoint(oldSession, href: 'saved.xhtml'),
        );
        final newSession = await store.beginSession('book', 'r1');
        await store.acceptCheckpoint(
          checkpoint(oldSession, sequence: 999, href: 'late.xhtml'),
        );
        expect(
          (await store.loadPosition('book', 'r1')).locatorJson,
          contains('saved.xhtml'),
        );
        await store.acceptCheckpoint(
          checkpoint(newSession, href: 'current.xhtml'),
        );
        expect(
          (await store.loadPosition('book', 'r1')).locatorJson,
          contains('current.xhtml'),
        );
      },
    );

    test(
      'revision mismatch and unknown sessions do not mutate stored state',
      () async {
        final session = await store.beginSession('book', 'r1');
        await store.acceptCheckpoint(checkpoint(session));
        await expectLater(
          store.acceptCheckpoint(checkpoint(session, revision: 'r2')),
          throwsFormatException,
        );
        await expectLater(
          store.acceptCheckpoint(
            checkpoint(
              const ReaderSessionIdentity(id: 'unknown', generation: 9),
            ),
          ),
          throwsFormatException,
        );
        expect((await store.loadPosition('book', 'r2')).locatorJson, isNull);
      },
    );

    test(
      'preferences-only event retains the locator and close does not erase it',
      () async {
        final session = await store.beginSession('book', 'r1');
        await store.acceptCheckpoint(checkpoint(session));
        final event = checkpoint(session, sequence: 2)
          ..kind = 'preferencesChanged'
          ..locatorJson = null
          ..preferences = ReaderPreferences(
            fontScale: 1.4,
            columnCount: 2,
            scroll: false,
            theme: 'sepia',
            fontId: 'maplestory',
          );
        await store.acceptCheckpoint(event);
        expect(
          (await store.loadPosition('book', 'r1')).preferences.fontId,
          'maplestory',
        );
        final saved = await store.loadPosition('book', 'r1');
        expect(saved.locatorJson, contains('chapter.xhtml'));
        expect(saved.preferences.fontScale, 1.4);
      },
    );

    test(
      'turn style change keeps exact anchor and survives a new session',
      () async {
        final session = await store.beginSession('book', 'r1');
        const anchor =
            '{"href":"chapter.xhtml","locations":{"koofyText":'
            '{"cssSelector":"#p60","textNodeIndex":0,"charOffset":17}},'
            '"text":{"highlight":"읽던 문장"}}';
        await store.acceptCheckpoint(checkpoint(session)..locatorJson = anchor);
        await store.acceptCheckpoint(
          checkpoint(session, sequence: 2)
            ..kind = 'preferencesChanged'
            ..locatorJson = null
            ..preferences!.pageTurnStyle = 'curl',
        );
        final saved = await store.loadPosition('book', 'r1');
        expect(saved.locatorJson, anchor);
        expect(saved.preferences.pageTurnStyle, 'curl');
        await store.beginSession('book', 'r1');
        // An unacknowledged checkpoint from the older session cannot reset style.
        await store.acceptCheckpoint(checkpoint(session, sequence: 999));
        final reopened = await store.loadPosition('book', 'r1');
        expect(reopened.locatorJson, anchor);
        expect(reopened.preferences.pageTurnStyle, 'curl');
        expect(
          (await store.loadPosition(
            'other-book',
            'r1',
          )).preferences.pageTurnStyle,
          'curl',
        );
      },
    );

    test(
      'invalid turn style cannot replace a committed reading record',
      () async {
        final session = await store.beginSession('book', 'r1');
        await store.acceptCheckpoint(checkpoint(session));
        final invalid = checkpoint(session, sequence: 2, href: 'wrong.xhtml')
          ..preferences!.pageTurnStyle = 'unknown';
        await expectLater(
          store.acceptCheckpoint(invalid),
          throwsFormatException,
        );
        final saved = await store.loadPosition('book', 'r1');
        expect(saved.locatorJson, contains('chapter.xhtml'));
        expect(saved.preferences.pageTurnStyle, 'instant');
      },
    );

    test(
      'malformed locator and invalid preferences fail transactionally',
      () async {
        final session = await store.beginSession('book', 'r1');
        final bad = checkpoint(session)..locatorJson = '{}';
        await expectLater(store.acceptCheckpoint(bad), throwsFormatException);
        bad.locatorJson = '{"href":"chapter.xhtml"}';
        bad.preferences!.fontScale = double.nan;
        await expectLater(store.acceptCheckpoint(bad), throwsFormatException);
        expect((await store.loadPosition('book', 'r1')).locatorJson, isNull);
      },
    );
  });

  test('session generation survives reopening the database file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'koofy-reader-db-test-',
    );
    final path = File('${directory.path}/reader.sqlite');
    try {
      final first = NativeReaderStore(NativeDatabase(path));
      final oldSession = await first.beginSession('book', 'r1');
      await first.acceptCheckpoint(
        checkpoint(oldSession)..preferences!.theme = 'dark',
      );
      await first.close();
      final reopened = NativeReaderStore(NativeDatabase(path));
      try {
        final newSession = await reopened.beginSession('book', 'r1');
        expect(newSession.generation, greaterThan(oldSession.generation));
        expect(
          (await reopened.loadPosition('new-book', 'r1')).preferences.theme,
          'dark',
        );
        expect(
          (await reopened.loadPosition('book', 'r1')).locatorJson,
          contains('chapter.xhtml'),
        );
      } finally {
        await reopened.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

class _V1ReaderStore extends NativeReaderStore {
  _V1ReaderStore(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE reader_counter (id INTEGER PRIMARY KEY, generation INTEGER NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE reader_sessions (session_id TEXT PRIMARY KEY, generation INTEGER NOT NULL UNIQUE, publication_id TEXT NOT NULL, content_revision TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE reader_positions (publication_id TEXT NOT NULL, content_revision TEXT NOT NULL, session_id TEXT NOT NULL, generation INTEGER NOT NULL, sequence INTEGER NOT NULL, locator_json TEXT, preferences_json TEXT NOT NULL, PRIMARY KEY(publication_id, content_revision))',
      );
    },
  );
}
