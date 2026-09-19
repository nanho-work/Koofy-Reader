import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/core/storage/storage_migration_runner.dart';
import 'package:koofy_reader/core/utils/hash_utils.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cutover preserves raw records, malformed data and all books exactly once',
    () async {
      final original = {
        'reader_progress_first': '{broken',
        'reader_progress_second': '{"positionRatio":0.2}',
        'reader_bookmark_first': '[0, 123, 456]',
        'reader_settings': '{"fontSize":19}',
      };
      SharedPreferences.setMockInitialValues(original);
      final storage = SharedPrefsLocalStorage();
      await StorageMigrationRunner(storage: storage).run();
      expect(
        jsonDecode((await storage.getString(LegacyReaderArchive.backupKey))!),
        original,
      );
      for (final entry in original.entries) {
        expect(await storage.getString(entry.key), entry.value);
      }
      await storage.setString(
        'reader_progress_first',
        'later external mutation',
      );
      await StorageMigrationRunner(storage: storage).run();
      expect(
        (await LegacyReaderArchive(storage).backup())['reader_progress_first'],
        '{broken',
      );
    },
  );

  test(
    'migration preserves canonical offset rather than earlier spread start',
    () async {
      SharedPreferences.setMockInitialValues({
        'reader_progress_book':
            '{"contentOffset":500,"doublePageStartOffset":300,"locator":{"globalOffset":510}}',
        'reader_bookmark_book': '[10,10,20,-3]',
      });
      final record = (await LegacyReaderArchive(
        SharedPrefsLocalStorage(),
      ).loadBook('book'))!;
      expect(record.offset, 510);
      expect(record.bookmarks, [10, 20]);
      expect(record.hasProgress, isTrue);
    },
  );

  test('ratio-only records never manufacture character offset zero', () async {
    SharedPreferences.setMockInitialValues({
      'reader_progress_book': '{"positionRatio":0.8}',
    });
    final record = (await LegacyReaderArchive(
      SharedPrefsLocalStorage(),
    ).loadBook('book'))!;
    expect(record.offset, isNull);
    expect(record.hasProgress, isTrue);
  });

  test(
    'TXT migration locators resolve into generated XHTML across chunks, blank lines and emoji',
    () async {
      final dir = await Directory.systemTemp.createTemp('koofy-migration-');
      addTearDown(() => dir.delete(recursive: true));
      final text = '첫 문장\n\n${'가' * 31999}😀${'나' * 120}\n마지막 문장';
      final file = File('${dir.path}/original.txt');
      await file.writeAsString(text.replaceAll('\n', '\r\n'));
      final book = Book.localFile(
        id: 'book',
        title: 'Book',
        author: '',
        description: '',
        localPath: file.path,
      );
      final prepared = await ReadingPublicationPreparer(
        storageDirectory: Directory('${dir.path}/owned'),
      ).prepare(book: book);
      final archive = ZipDecoder().decodeBytes(
        await File(prepared.filePath).readAsBytes(),
      );
      final map = prepared.textMap!;
      expect(map.text, text);
      for (final offset in [
        0,
        5,
        100,
        text.indexOf('😀'),
        text.indexOf('😀') + 1,
        text.indexOf('마지막'),
      ]) {
        final locator = jsonDecode(map.locatorAt(offset)!);
        final locations = locator['locations'];
        final point = locations['koofyText'];
        final doc = XmlDocument.parse(
          utf8.decode(archive.findFile(locator['href'])!.content),
        );
        final id = (point['cssSelector'] as String).substring(1);
        final element = doc.descendants.whereType<XmlElement>().singleWhere(
          (e) => e.getAttribute('id') == id,
        );
        final at = point['charOffset'] as int;
        final quote = locator['text']['highlight'] as String;
        expect(element.innerText.substring(at, at + quote.length), quote);
        expect(quote.runes, hasLength(1));
      }
      expect(map.locatorAt(-1), isNull);
      expect(map.locatorAt(text.length + 1), isNull);

      SharedPreferences.setMockInitialValues({
        'reader_progress_book': '{"contentOffset":100}',
      });
      final cache = File(
        '${dir.path}/reader_content_cache/${HashUtils.fnv1a32('book')}.json',
      );
      await cache.parent.create(recursive: true);
      await cache.writeAsString(jsonEncode({'normalizedContent': text}));
      final records = LegacyReaderArchive(SharedPrefsLocalStorage());
      expect(
        (await records.loadBook('book', support: dir))!.cachedText,
        map.text,
      );
      await cache.writeAsString(jsonEncode({'normalizedContent': 'changed'}));
      expect((await records.loadBook('book', support: dir))!.cachedText, text);
    },
  );
}
