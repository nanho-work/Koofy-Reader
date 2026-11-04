import 'dart:io';
import 'package:koofy_reader/features/backup/data/library_backup.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reading_diary/data/reading_diary.dart';
import 'library_backup_test.dart' show MemoryBackupStorage, BackupFixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'library ZIP preserves deleted-book diary covers and deduplicates them',
    () async {
      final source = BackupFixture(
        await Directory.systemTemp.createTemp('diary-source'),
      );
      final target = BackupFixture(
        await Directory.systemTemp.createTemp('diary-target'),
      );
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      // A tiny PNG is enough for this archive roundtrip; no library book remains.
      const cover =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9K8AAAAASUVORK5CYII=';
      final diary = ReadingDiary(source.storage);
      for (final day in [1, 2]) {
        await diary.add(
          const DiaryBook(
            id: 'deleted',
            title: 'A retained book',
            cover: cover,
          ),
          DateTime(2026, 11, day),
          const Duration(minutes: 40),
        );
      }
      final decoded = LibraryBackupService.decode(
        await source.service.export(),
      );
      expect(
        decoded.files.values.where((b) => base64Encode(b) == cover),
        hasLength(1),
      );
      await target.service.restore(decoded);
      await target.service.restore(decoded);
      final restored = await ReadingDiary(target.storage).load();
      expect(restored, hasLength(2));
      expect(restored.first.entries.single.book.cover, cover);
      expect(restored.first.duration.inMinutes, 40);
    },
  );

  test(
    'splits at local midnight, serializes concurrent writes and retains group chapters',
    () async {
      final storage = MemoryBackupStorage();
      final diary = ReadingDiary(storage);
      const book = DiaryBook(
        id: 'group_1',
        title: 'Collected stories',
        memberTitle: 'Chapter 1',
      );
      await Future.wait([
        diary.add(
          book,
          DateTime(2026, 11, 1, 23, 59, 50),
          const Duration(seconds: 30),
        ),
        diary.add(
          const DiaryBook(
            id: 'group_1',
            title: 'Collected stories',
            memberTitle: 'Chapter 2',
          ),
          DateTime(2026, 11, 2, 12),
          const Duration(minutes: 5),
        ),
      ]);
      final rows = await diary.load();
      expect(rows.map((r) => r.date), ['2026-11-01', '2026-11-02']);
      expect(rows.first.duration.inSeconds, 10);
      expect(rows.last.duration.inSeconds, 320);
      expect(rows.last.entries.single.members, {
        'Chapter 1': 20000,
        'Chapter 2': 300000,
      });
      // A new repository reads the durable journal independently of the library.
      expect(
        (await ReadingDiary(storage).load()).last.entries.single.book.title,
        'Collected stories',
      );
    },
  );
  test('backup merge is idempotent and supports old backups', () async {
    final storage = MemoryBackupStorage();
    final diary = ReadingDiary(storage);
    await diary.add(
      const DiaryBook(id: 'book', title: 'Deleted book'),
      DateTime(2026, 10, 2),
      const Duration(minutes: 20),
    );
    final backup = (await diary.load()).map((d) => d.toJson()).toList();
    for (var i = 0; i < 2; i++) {
      final pending = await ReadingDiary.mergeBackup(storage, backup);
      for (final e in pending.entries) {
        await storage.setString(e.key, e.value);
      }
    }
    expect((await diary.load()).single.duration.inMinutes, 20);
    expect(ReadingDiary.validateBackup(null), isEmpty);
    expect(jsonEncode(backup), isNot(contains('localPath')));
    expect(
      () => ReadingDiary.validateBackup([
        {'date': '2026-02-31', 'entries': []},
      ]),
      throwsFormatException,
    );
    expect(
      () => ReadingDiary.validateBackup([
        {
          'date': '2026-11-01',
          'entries': [
            {'id': 'x', 'title': 'x', 'milliseconds': -1},
          ],
        },
      ]),
      throwsFormatException,
    );
  });
}
