import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/bundled_books.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'fresh library has two covered books; hidden sample stays hidden',
    () async {
      final storage = SharedPrefsLocalStorage();
      final temporary = await Directory.systemTemp.createTemp(
        'bundle-library-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final repository = LocalBookRepository(
        storage,
        covers: BookCoverStore(storage, directory: () async => temporary),
      );
      final books = await repository.getBooks();
      expect(books.map((book) => book.id), [
        BundledBooks.mermaidId,
        'sample_2',
      ]);
      expect(books.every((book) => book.coverAssetPath != null), isTrue);
      await repository.removeBookFromLibrary(BundledBooks.mermaidId);
      expect(
        (await LocalBookRepository(
          storage,
          covers: BookCoverStore(storage, directory: () async => temporary),
        ).getBooks()).map((b) => b.id),
        ['sample_2'],
      );
    },
  );

  test(
    'old progress retains the old story under its original identity',
    () async {
      SharedPreferences.setMockInitialValues({
        'reader_progress_sample_1': 'old-position',
      });
      final storage = SharedPrefsLocalStorage();
      final books = await LocalBookRepository(storage).getBooks();
      expect(books.map((b) => b.id), containsAll(BundledBooks.ids));
      expect(
        books.singleWhere((b) => b.id == 'sample_1').assetPath,
        'assets/books/sample_1.txt',
      );
      expect(
        await storage.getString('reader_progress_sample_1'),
        'old-position',
      );
      expect(
        await storage.getString('reader_progress_${BundledBooks.mermaidId}'),
        isNull,
      );
      expect(await storage.getString(BundledBooks.retainLegacyKey), 'true');
    },
  );

  test(
    'previously prepared native sample remains available across restart',
    () async {
      final storage = SharedPrefsLocalStorage();
      final repository = LocalBookRepository(
        storage,
        hasLegacyPublication: () async => true,
      );
      expect(
        (await repository.getBooks()).map((b) => b.id),
        contains('sample_1'),
      );
      expect(
        (await LocalBookRepository(storage).getBooks()).map((b) => b.id),
        contains('sample_1'),
      );
    },
  );

  test(
    'sample keeps original TXT, adds a separate end page and optional cover',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bundled-publication-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final preparer = ReadingPublicationPreparer(storageDirectory: directory);
      final source = await rootBundle.load(BundledBooks.mermaid.assetPath!);
      final backedUp = await preparer.backupSource(BundledBooks.mermaid);
      expect(
        backedUp.bytes,
        source.buffer.asUint8List(source.offsetInBytes, source.lengthInBytes),
      );
      final publication = await preparer.prepare(book: BundledBooks.mermaid);
      expect(publication.hasDisplayCover, isTrue);
      final archive = ZipDecoder().decodeBytes(
        await File(publication.filePath).readAsBytes(),
      );
      final opf = XmlDocument.parse(
        utf8.decode(archive.findFile('EPUB/package.opf')!.content),
      );
      expect(
        opf.findAllElements('itemref').last.getAttribute('idref'),
        'continue',
      );
      final end = XmlDocument.parse(
        utf8.decode(archive.findFile('EPUB/continue.xhtml')!.content),
      );
      expect(
        end.findAllElements('a').single.getAttribute('href'),
        BundledBooks.continuationUrl,
      );
      expect(end.innerText, contains('아직 다음 화가 없다면'));
      final uncovered = await preparer.prepare(
        book: BundledBooks.mermaid,
        showRegisteredCover: false,
      );
      expect(uncovered.contentRevision, publication.contentRevision);
      expect(uncovered.hasDisplayCover, isFalse);
      // Importing the same TXT as a personal book never injects a catalog link.
      final copy = await File(
        '${directory.path}/copy.txt',
      ).writeAsBytes(backedUp.bytes);
      final imported = await preparer.prepare(
        book: Book.localFile(
          id: 'personal',
          title: '개인 책',
          author: '',
          description: '',
          localPath: copy.path,
        ),
      );
      expect(
        ZipDecoder()
            .decodeBytes(await File(imported.filePath).readAsBytes())
            .findFile('EPUB/continue.xhtml'),
        isNull,
      );
      if (const bool.fromEnvironment('GENERATE_BUNDLED_FIXTURE')) {
        await Directory('work/bundled-books').create(recursive: true);
        await File(
          publication.filePath,
        ).copy('work/bundled-books/mermaid.epub');
      }
    },
  );

  test('guide title and cover preserve its previous body revision', () async {
    final directory = await Directory.systemTemp.createTemp(
      'guide-publication-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final preparer = ReadingPublicationPreparer(storageDirectory: directory);
    final previous = await preparer.prepare(
      book: Book.asset(
        id: 'old-guide-fixture',
        title: '사용 방법 안내',
        author: 'Koofy Team',
        description: '',
        assetPath: 'assets/books/sample_2.txt',
      ),
    );
    final guide = await preparer.prepare(book: BundledBooks.guide);
    expect(guide.title, '쿠피리더 시작하기');
    expect(guide.contentRevision, previous.contentRevision);
    expect(guide.hasDisplayCover, isTrue);
    final original = await rootBundle.load('assets/books/sample_2.txt');
    final savedSource = await preparer.backupSource(BundledBooks.guide);
    expect(
      sha256.convert(savedSource.bytes),
      sha256.convert(original.buffer.asUint8List()),
    );
  });
}
