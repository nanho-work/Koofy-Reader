import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/bundled_books.dart';
import 'package:koofy_reader/features/library/domain/reader_guide.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'guide languages keep identity, translated contents, and separate positions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'localized-guide-',
      );
      final store = NativeReaderStore(NativeDatabase.memory());
      addTearDown(() async {
        await AppLanguage.instance.select('ko');
        await store.close();
        await directory.delete(recursive: true);
      });
      final preparer = ReadingPublicationPreparer(storageDirectory: directory);
      final revisions = <String, String>{};
      int? chapterCount;
      final canonical = BundledBooks.guide.toJson();
      for (final lang in ['ko', 'en', 'ja']) {
        await AppLanguage.instance.select(lang);
        final book = BundledBooks.guide.withCoverPath(null);
        expect(book.id, 'sample_2');
        expect(book.assetPath, ReaderGuide.canonicalAsset);
        expect(book.title, ReaderGuide.title);
        expect(book.toJson(), canonical);
        expect(Book.fromJson(canonical)!.title, ReaderGuide.title);
        final prepared = await preparer.prepare(book: book);
        expect(prepared.publicationId, book.id);
        expect(prepared.title, ReaderGuide.title);
        expect(prepared.hasDisplayCover, isTrue);
        revisions[lang] = prepared.contentRevision;
        final archive = ZipDecoder().decodeBytes(
          await File(prepared.filePath).readAsBytes(),
        );
        String text(String path) => utf8.decode(
          archive.files.firstWhere((f) => f.name == path).content,
        );
        final nav = XmlDocument.parse(text('EPUB/nav.xhtml'));
        final links = nav
            .findAllElements('a')
            .where((e) => !['표지', 'Cover', '表紙'].contains(e.innerText))
            .toList();
        chapterCount ??= links.length;
        expect(links.length, chapterCount);
        expect(links.length, greaterThan(30));
        expect(links.first.innerText, switch (lang) {
          'en' => 'Getting started with Koofy Reader',
          'ja' => 'Koofy Readerをはじめよう',
          _ => '쿠피리더, 이렇게 시작하세요',
        });
        expect(
          text('EPUB/package.opf'),
          contains('<dc:language>${lang == 'ko' ? 'und' : lang}</dc:language>'),
        );
        if (lang != 'ko') {
          expect(
            nav.findAllElements('h1').single.innerText,
            lang == 'en' ? 'Contents' : '目次',
          );
        }
        final session = await store.beginSession(
          book.id,
          prepared.contentRevision,
        );
        final locator = jsonEncode({
          'href': 'section-000.xhtml',
          'type': 'application/xhtml+xml',
          'locations': {'progression': 0.2},
        });
        await store.acceptCheckpoint(
          ReaderEvent(
            protocolVersion: 1,
            sessionId: session.id,
            sessionGeneration: session.generation,
            publicationId: book.id,
            contentRevision: prepared.contentRevision,
            sequence: 1,
            kind: 'locationChanged',
            locatorJson: locator,
            preferences: defaultReaderPreferences(),
          ),
        );
        if (const bool.fromEnvironment('GENERATE_GUIDE_PREVIEW')) {
          final out = Directory('work/localization/guides');
          await out.create(recursive: true);
          await File(prepared.filePath).copy('${out.path}/guide-$lang.epub');
        }
      }
      expect(revisions.values.toSet().length, 3);
      for (final lang in ['en', 'ko', 'ja']) {
        await AppLanguage.instance.select(lang);
        final prepared = await preparer.prepare(book: BundledBooks.guide);
        expect(prepared.contentRevision, revisions[lang]);
        final position = await store.loadPosition(
          prepared.publicationId,
          prepared.contentRevision,
        );
        expect(position.locatorJson, contains('section-000.xhtml'));
        expect(position.previousRevisionExists, isFalse);
      }
    },
  );

  test('ordinary books do not change with the app language', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('unchanged-book-');
    addTearDown(() async {
      await AppLanguage.instance.select('ko');
      await directory.delete(recursive: true);
    });
    final preparer = ReadingPublicationPreparer(storageDirectory: directory);
    String? revision;
    for (final lang in ['ko', 'en', 'ja']) {
      await AppLanguage.instance.select(lang);
      expect(BundledBooks.mermaid.title, '인어공주는 파도를 벤다 1화');
      final prepared = await preparer.prepare(
        book: BundledBooks.mermaid,
        showRegisteredCover: false,
      );
      revision ??= prepared.contentRevision;
      expect(prepared.contentRevision, revision);
    }
  });
}
