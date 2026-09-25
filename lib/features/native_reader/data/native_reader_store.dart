import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';

class StoredReaderPosition {
  const StoredReaderPosition({
    required this.locatorJson,
    required this.preferences,
    this.previousRevisionExists = false,
    this.bookmarksJson = '[]',
  });
  final String? locatorJson;
  final ReaderPreferences preferences;
  final bool previousRevisionExists;
  final String bookmarksJson;
}

class ReaderSessionIdentity {
  const ReaderSessionIdentity({required this.id, required this.generation});
  final String id;
  final int generation;
}

class NativeLibraryPosition {
  const NativeLibraryPosition({
    required this.publicationId,
    required this.locatorJson,
    required this.lastOpenedAt,
  });
  final String publicationId;
  final String locatorJson;
  final DateTime? lastOpenedAt;
}

ReaderPreferences defaultReaderPreferences() => ReaderPreferences(
  fontScale: 1.0,
  columnCount: 0,
  scroll: false,
  theme: 'light',
  pageTurnStyle: 'instant',
  fontId: 'default',
);

/// G1's small, explicit SQL schema. No streams depend on generated table metadata.
/// This is the only writer of the native reader's domain records.
class NativeReaderStore extends GeneratedDatabase {
  NativeReaderStore(super.executor);

  factory NativeReaderStore.open(File file) =>
      NativeReaderStore(NativeDatabase.createInBackground(file));

  @override
  int get schemaVersion => 4;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE reader_counter (id INTEGER PRIMARY KEY CHECK(id=1), generation INTEGER NOT NULL)',
      );
      await customStatement('INSERT INTO reader_counter VALUES (1, 0)');
      await customStatement('''CREATE TABLE reader_sessions (
        session_id TEXT PRIMARY KEY, generation INTEGER NOT NULL UNIQUE,
        publication_id TEXT NOT NULL, content_revision TEXT NOT NULL,
        started_at INTEGER)''');
      await customStatement('''CREATE TABLE reader_positions (
        publication_id TEXT NOT NULL, content_revision TEXT NOT NULL,
        session_id TEXT NOT NULL, generation INTEGER NOT NULL,
        sequence INTEGER NOT NULL, locator_json TEXT,
        preferences_json TEXT NOT NULL, bookmarks_json TEXT NOT NULL DEFAULT '[]',
        PRIMARY KEY(publication_id, content_revision))''');
      await _createGlobalPreferences();
    },
    onUpgrade: (_, from, to) async {
      if (from < 4) {
        await customStatement(
          "ALTER TABLE reader_positions ADD COLUMN bookmarks_json TEXT NOT NULL DEFAULT '[]'",
        );
      }
      if (from < 2) {
        // Existing sessions have no trustworthy wall-clock timestamp.
        await customStatement(
          'ALTER TABLE reader_sessions ADD COLUMN started_at INTEGER',
        );
      }
      if (from < 3) {
        await _createGlobalPreferences();
        // Preserve the last used appearance when upgrading from per-book settings.
        await customStatement('''INSERT INTO reader_preferences
          SELECT 1, generation, sequence, preferences_json FROM reader_positions
          ORDER BY generation DESC, sequence DESC LIMIT 1''');
      }
    },
  );

  Future<void> _createGlobalPreferences() => customStatement('''
    CREATE TABLE reader_preferences (
      id INTEGER PRIMARY KEY CHECK(id=1), generation INTEGER NOT NULL,
      sequence INTEGER NOT NULL, preferences_json TEXT NOT NULL)''');

  Future<ReaderPreferences> _loadGlobalPreferences() async {
    final row = await customSelect(
      'SELECT preferences_json FROM reader_preferences WHERE id=1',
    ).getSingleOrNull();
    return row == null
        ? defaultReaderPreferences()
        : preferencesFromJson(row.read<String>('preferences_json'));
  }

  Future<ReaderSessionIdentity> beginSession(
    String publicationId,
    String revision,
  ) {
    return transaction(() async {
      await customStatement(
        'UPDATE reader_counter SET generation=generation+1 WHERE id=1',
      );
      final row = await customSelect(
        'SELECT generation FROM reader_counter WHERE id=1',
      ).getSingle();
      final generation = row.read<int>('generation');
      final random = Random.secure();
      final token = List.generate(
        12,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final identity = ReaderSessionIdentity(
        id: '$generation-$token',
        generation: generation,
      );
      await customStatement(
        'INSERT INTO reader_sessions VALUES (?, ?, ?, ?, ?)',
        [
          identity.id,
          generation,
          publicationId,
          revision,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      return identity;
    });
  }

  /// The last committed session per book. Recovery time must not make an old
  /// journal entry appear newer than a book the user opened afterwards.
  Future<List<NativeLibraryPosition>> loadLibraryPositions() async {
    final rows = await customSelect('''
      SELECT p.publication_id, p.locator_json, s.started_at
      FROM reader_positions p JOIN reader_sessions s ON s.session_id=p.session_id
      WHERE p.locator_json IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM reader_positions newer
        WHERE newer.publication_id=p.publication_id
          AND newer.locator_json IS NOT NULL AND newer.generation>p.generation
      )''').get();
    return rows.map((row) {
      final timestamp = row.readNullable<int>('started_at');
      return NativeLibraryPosition(
        publicationId: row.read<String>('publication_id'),
        locatorJson: row.read<String>('locator_json'),
        lastOpenedAt: timestamp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    }).toList();
  }

  Future<StoredReaderPosition> loadPosition(
    String publicationId,
    String revision,
  ) async {
    final preferences = await _loadGlobalPreferences();
    final row = await customSelect(
      'SELECT locator_json, preferences_json, bookmarks_json FROM reader_positions WHERE publication_id=? AND content_revision=?',
      variables: [
        Variable.withString(publicationId),
        Variable.withString(revision),
      ],
    ).getSingleOrNull();
    if (row == null) {
      final previous = await customSelect(
        'SELECT 1 FROM reader_positions WHERE publication_id=? AND content_revision<>? AND locator_json IS NOT NULL LIMIT 1',
        variables: [
          Variable.withString(publicationId),
          Variable.withString(revision),
        ],
      ).getSingleOrNull();
      return StoredReaderPosition(
        locatorJson: null,
        preferences: preferences,
        previousRevisionExists: previous != null,
      );
    }
    return StoredReaderPosition(
      locatorJson: row.readNullable<String>('locator_json'),
      bookmarksJson: row.read<String>('bookmarks_json'),
      preferences: preferences,
    );
  }

  Future<Map<String, dynamic>> exportBackup(Set<String> bookIds) =>
      transaction(() async {
        final rows = await customSelect(
          '''SELECT p.publication_id, p.content_revision,
      p.locator_json, p.bookmarks_json, s.started_at FROM reader_positions p
      JOIN reader_sessions s ON p.session_id=s.session_id ORDER BY p.generation''',
        ).get();
        return {
          'preferences': preferencesToJson(await _loadGlobalPreferences()),
          'positions': [
            for (final row in rows)
              if (bookIds.contains(row.read<String>('publication_id')))
                {
                  'bookId': row.read<String>('publication_id'),
                  'revision': row.read<String>('content_revision'),
                  'locator': row.readNullable<String>('locator_json'),
                  'bookmarks': row.read<String>('bookmarks_json'),
                  'openedAt': row.readNullable<int>('started_at'),
                },
          ],
        };
      });

  /// Merge missing books' records only. Session identities are always allocated
  /// locally, so an old native journal cannot overwrite restored reading state.
  Future<void> mergeBackup(
    Map<String, dynamic> backup,
    Set<String> bookIds,
    Future<void> Function() commitLibrary,
  ) => transaction(() async {
    final preferences = preferencesFromJson(backup['preferences'] as String);
    final existingIds = (await customSelect(
      'SELECT DISTINCT publication_id FROM reader_positions',
    ).get()).map((r) => r.read<String>('publication_id')).toSet();
    final existingPreferences = await customSelect(
      'SELECT 1 FROM reader_preferences WHERE id=1',
    ).getSingleOrNull();
    for (final raw in backup['positions'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['bookId'] as String;
      if (!bookIds.contains(id) || existingIds.contains(id)) continue;
      final session = await beginSession(id, row['revision'] as String);
      await customStatement(
        'UPDATE reader_sessions SET started_at=? WHERE session_id=?',
        [row['openedAt'], session.id],
      );
      await customStatement(
        'INSERT INTO reader_positions VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          row['revision'],
          session.id,
          session.generation,
          0,
          row['locator'],
          preferencesToJson(preferences),
          validateBookmarksJson(row['bookmarks'] as String? ?? '[]'),
        ],
      );
    }
    if (existingPreferences == null) {
      // Remote font binaries are re-downloaded on the destination device.
      if (preferences.fontId?.startsWith('remote_') == true) {
        preferences.fontId = 'default';
      }
      final generation = (await customSelect(
        'SELECT generation FROM reader_counter WHERE id=1',
      ).getSingle()).read<int>('generation');
      await customStatement(
        'INSERT INTO reader_preferences VALUES (1, ?, 0, ?)',
        [generation, preferencesToJson(preferences)],
      );
    }
    await commitLibrary();
  });

  /// Return after a committed write or a validated stale/duplicate no-op.
  /// Malformed/unknown events throw, so the native journal remains recoverable.
  Future<void> acceptCheckpoint(ReaderEvent event) => transaction(() async {
    if (event.protocolVersion != 1 ||
        event.sequence < 0 ||
        !const {
          'ready',
          'locationChanged',
          'preferencesChanged',
          'closed',
        }.contains(event.kind)) {
      throw const FormatException('지원하지 않는 독서 기록 형식입니다.');
    }
    final session = await customSelect(
      'SELECT generation, publication_id, content_revision FROM reader_sessions WHERE session_id=?',
      variables: [Variable.withString(event.sessionId)],
    ).getSingleOrNull();
    if (session == null ||
        session.read<int>('generation') != event.sessionGeneration ||
        session.read<String>('publication_id') != event.publicationId ||
        session.read<String>('content_revision') != event.contentRevision) {
      throw const FormatException('독서 기록의 세션 또는 책 버전이 일치하지 않습니다.');
    }
    if (event.locatorJson != null) {
      final locator = jsonDecode(event.locatorJson!);
      if (locator is! Map<String, dynamic> ||
          locator['href'] is! String ||
          (locator['href'] as String).isEmpty) {
        throw const FormatException('올바르지 않은 본문 위치입니다.');
      }
    }
    final rows = await customSelect(
      'SELECT generation, sequence, locator_json, preferences_json, bookmarks_json FROM reader_positions WHERE publication_id=? AND content_revision=?',
      variables: [
        Variable.withString(event.publicationId),
        Variable.withString(event.contentRevision),
      ],
    ).getSingleOrNull();
    final latestSession = await customSelect(
      'SELECT MAX(generation) AS generation FROM reader_sessions WHERE publication_id=? AND content_revision=?',
      variables: [
        Variable.withString(event.publicationId),
        Variable.withString(event.contentRevision),
      ],
    ).getSingle();
    if (event.sessionGeneration < latestSession.read<int>('generation')) return;
    if (rows != null &&
        (rows.read<int>('generation') > event.sessionGeneration ||
            (rows.read<int>('generation') == event.sessionGeneration &&
                rows.read<int>('sequence') >= event.sequence))) {
      return;
    }
    final bookmarks = validateBookmarksJson(
      event.bookmarksJson ?? rows?.read<String>('bookmarks_json') ?? '[]',
    );
    final locator =
        event.locatorJson ?? rows?.readNullable<String>('locator_json');
    final preferences = event.preferences == null
        ? (rows?.read<String>('preferences_json') ??
              preferencesToJson(defaultReaderPreferences()))
        : preferencesToJson(event.preferences!);
    if (event.preferences != null) {
      // Old journals from a different book may still restore that book's location,
      // but must never roll back the current app-wide appearance.
      final latest = await customSelect(
        'SELECT generation FROM reader_counter WHERE id=1',
      ).getSingle();
      if (event.sessionGeneration == latest.read<int>('generation')) {
        await customStatement(
          '''INSERT INTO reader_preferences
          (id, generation, sequence, preferences_json) VALUES (1, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET generation=excluded.generation,
          sequence=excluded.sequence, preferences_json=excluded.preferences_json
          WHERE excluded.generation > reader_preferences.generation OR
            (excluded.generation = reader_preferences.generation AND
             excluded.sequence > reader_preferences.sequence)''',
          [event.sessionGeneration, event.sequence, preferences],
        );
      }
    }
    await customStatement(
      '''INSERT INTO reader_positions
      (publication_id, content_revision, session_id, generation, sequence, locator_json, preferences_json, bookmarks_json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(publication_id, content_revision) DO UPDATE SET
      session_id=excluded.session_id, generation=excluded.generation,
      sequence=excluded.sequence, locator_json=excluded.locator_json,
      preferences_json=excluded.preferences_json, bookmarks_json=excluded.bookmarks_json''',
      [
        event.publicationId,
        event.contentRevision,
        event.sessionId,
        event.sessionGeneration,
        event.sequence,
        locator,
        preferences,
        bookmarks,
      ],
    );
  });
}

String preferencesToJson(ReaderPreferences value) {
  if (!value.fontScale.isFinite ||
      value.fontScale < 0.5 ||
      value.fontScale > 4 ||
      !const [0, 1, 2].contains(value.columnCount) ||
      !const ['light', 'sepia', 'dark'].contains(value.theme) ||
      !const ['instant', 'curl'].contains(value.pageTurnStyle ?? 'instant') ||
      (!const [
            'default',
            'maplestory',
            'hakgyoansim-siganpyo',
          ].contains(value.fontId ?? 'default') &&
          !RegExp(r'^remote_[a-f0-9]{32}$').hasMatch(value.fontId ?? ''))) {
    throw const FormatException('지원하지 않는 독서 설정입니다.');
  }
  return jsonEncode({
    'fontScale': value.fontScale,
    'columnCount': value.columnCount,
    'scroll': value.scroll,
    'theme': value.theme,
    'pageTurnStyle': value.pageTurnStyle ?? 'instant',
    'fontId': value.fontId ?? 'default',
  });
}

ReaderPreferences preferencesFromJson(String source) {
  final json = jsonDecode(source) as Map<String, dynamic>;
  final preferences = ReaderPreferences(
    fontScale: (json['fontScale'] as num).toDouble(),
    columnCount: json['columnCount'] as int,
    scroll: json['scroll'] as bool,
    theme: json['theme'] as String,
    pageTurnStyle: json['pageTurnStyle'] as String? ?? 'instant',
    fontId: json['fontId'] as String? ?? 'default',
  );
  preferencesToJson(preferences);
  return preferences;
}

/// Validate snapshots both from native recovery and untrusted backup files.
String validateBookmarksJson(String value) {
  if (utf8.encode(value).length > 512 * 1024) {
    throw const FormatException('책갈피가 너무 큽니다.');
  }
  final rows = jsonDecode(value);
  if (rows is! List || rows.length > 100) {
    throw const FormatException('책갈피 형식이 올바르지 않습니다.');
  }
  final ids = <String>{};
  for (final row in rows) {
    if (row is! Map ||
        row['id'] is! String ||
        (row['id'] as String).isEmpty ||
        !ids.add(row['id'] as String) ||
        row['label'] is! String ||
        (row['label'] as String).length > 300 ||
        row['locator'] is! Map ||
        row['locator']['href'] is! String ||
        (row['locator']['href'] as String).isEmpty) {
      throw const FormatException('책갈피 위치가 올바르지 않습니다.');
    }
  }
  return value;
}
