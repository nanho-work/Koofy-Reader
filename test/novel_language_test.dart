import 'dart:convert';
import 'dart:io';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/domain/bundled_books.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
  });
  test(
    'one bundled novel per language with independent book identities',
    () async {
      final dir = await Directory.systemTemp.createTemp('novel-library-');
      addTearDown(() => dir.delete(recursive: true));
      final storage = SharedPrefsLocalStorage();
      final repo = LocalBookRepository(
        storage,
        covers: BookCoverStore(storage, directory: () async => dir),
        hasLegacyPublication: () async => false,
      );
      final seen = <String>{};
      for (final lang in ['ko', 'en', 'ja']) {
        await AppLanguage.instance.select(lang);
        final books = await repo.getBooks();
        final novels = books.where(BundledBooks.hasContinuation).toList();
        expect(novels.length, 1);
        expect(BundledBooks.languageOf(novels.single), lang);
        expect(seen.add(novels.single.id), isTrue);
      }
      await AppLanguage.instance.select('en');
      await repo.removeBookFromLibrary(BundledBooks.mermaidEn.id);
      await AppLanguage.instance.select('ko');
      expect(
        (await repo.getBooks()).any((b) => b.id == BundledBooks.mermaidId),
        isTrue,
      );
      await AppLanguage.instance.select('en');
      expect(
        (await repo.getBooks()).any((b) => b.id == BundledBooks.mermaidEn.id),
        isFalse,
      );
    },
  );
  test(
    'translated novel packages have matching language, body and continuation',
    () async {
      final dir = await Directory.systemTemp.createTemp('novel-language-');
      addTearDown(() => dir.delete(recursive: true));
      final preparer = ReadingPublicationPreparer(storageDirectory: dir);
      for (final book in [BundledBooks.mermaidEn, BundledBooks.mermaidJa]) {
        final result = await preparer.prepare(book: book);
        final archive = ZipDecoder().decodeBytes(
          await File(result.filePath).readAsBytes(),
        );
        final language = BundledBooks.languageOf(book);
        expect(
          utf8.decode(archive.findFile('EPUB/package.opf')!.content),
          contains('<dc:language>$language</dc:language>'),
        );
        final next = utf8.decode(
          archive.findFile('EPUB/continue.xhtml')!.content,
        );
        expect(next, contains(BundledBooks.continuationUrl));
        expect(
          next,
          contains(language == 'en' ? 'The story continues' : '物語は続きます'),
        );
        expect(next, isNot(contains('다음 이야기')));
        expect(result.publicationId, book.id);
      }
    },
  );
}
