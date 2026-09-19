import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late ReadingPublicationPreparer preparer;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'koofy-publication-test-',
    );
    preparer = ReadingPublicationPreparer(
      storageDirectory: Directory('${temporary.path}/owned'),
    );
  });
  tearDown(() async => temporary.delete(recursive: true));

  Future<Book> source(
    List<int> bytes, {
    String extension = 'txt',
    String id = 'book-1',
  }) async {
    final file = File('${temporary.path}/책 원본.$extension');
    await file.writeAsBytes(bytes);
    return Book.localFile(
      id: id,
      title: '책 & <제목>',
      author: '작가',
      description: '',
      localPath: file.path,
    );
  }

  Matcher preparationError(String code) =>
      isA<ReadingPublicationPreparationException>().having(
        (error) => error.code,
        'code',
        code,
      );

  test(
    'TXT creates stable EPUB3 with stored first mimetype and preserved text',
    () async {
      const original = '첫 문장 & <본문>\r\n\r\n  두 번째 😀\r마지막';
      final book = await source(utf8.encode(original));
      final first = await preparer.prepare(book: book);
      final second = await preparer.prepare(book: book);
      expect(first.publicationId, book.id);
      expect(second.contentRevision, first.contentRevision);
      expect(second.filePath, first.filePath);
      final bytes = await File(first.filePath).readAsBytes();
      expect(first.contentRevision, 'epub-sha256:${sha256.convert(bytes)}');
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.first.name, 'mimetype');
      expect(zip.files.first.compression, CompressionType.none);
      expect(utf8.decode(zip.files.first.content), 'application/epub+zip');
      final package = XmlDocument.parse(
        utf8.decode(zip.findFile('EPUB/package.opf')!.content),
      );
      expect(package.rootElement.getAttribute('version'), '3.0');
      expect(package.findAllElements('dc:title').single.innerText, book.title);
      final chapter = XmlDocument.parse(
        utf8.decode(zip.findFile('EPUB/section-00000.xhtml')!.content),
      );
      final paragraphs = chapter.findAllElements('p').toList();
      expect(paragraphs.map((node) => node.innerText), [
        '첫 문장 & <본문>',
        '',
        '  두 번째 😀',
        '마지막',
      ]);
      expect(
        paragraphs.map((node) => node.getAttribute('id')).toSet().length,
        4,
      );
      expect(await File(book.localPath!).readAsString(), original);
      final ownedSource = File(
        '${File(first.filePath).parent.path}/source.txt',
      );
      expect(await ownedSource.readAsString(), original);
      // Ensure generated EPUB is also accepted by the supported-subset validator.
      final generatedBook = Book.localFile(
        id: 'generated',
        title: book.title,
        author: book.author,
        description: '',
        localPath: first.filePath,
      );
      final generated = await preparer.prepare(book: generatedBook);
      expect(await File(generated.filePath).readAsBytes(), bytes);
    },
  );

  test(
    'retained original survives removal and repairs a damaged rendered copy',
    () async {
      final book = await source(utf8.encode('보관할 본문'));
      final first = await preparer.prepare(book: book);
      final bytes = await File(first.filePath).readAsBytes();
      await File(book.localPath!).delete();
      await File(first.filePath).writeAsString('corrupt');
      final restored = await preparer.prepare(book: book);
      expect(restored.contentRevision, first.contentRevision);
      expect(await File(restored.filePath).readAsBytes(), bytes);
    },
  );

  test(
    'changed source keeps book identity but changes content revision',
    () async {
      final book = await source(utf8.encode('원래 본문'));
      final first = await preparer.prepare(book: book);
      await File(book.localPath!).writeAsString('수정된 본문');
      final changed = await preparer.prepare(book: book);
      expect(changed.publicationId, first.publicationId);
      expect(changed.contentRevision, isNot(first.contentRevision));
      expect(await File(first.filePath).exists(), isTrue);
    },
  );

  for (final littleEndian in [true, false]) {
    test(
      'UTF16 ${littleEndian ? 'LE' : 'BE'} BOM preserves Korean and surrogate pair',
      () async {
        const text = '한글 😀\r\n다음 줄';
        final bytes = <int>[
          if (littleEndian) ...[0xff, 0xfe] else ...[0xfe, 0xff],
        ];
        for (final unit in text.codeUnits) {
          bytes.addAll(
            littleEndian ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255],
          );
        }
        final result = await preparer.prepare(book: await source(bytes));
        final zip = ZipDecoder().decodeBytes(
          await File(result.filePath).readAsBytes(),
        );
        final chapter = XmlDocument.parse(
          utf8.decode(zip.findFile('EPUB/section-00000.xhtml')!.content),
        );
        expect(chapter.findAllElements('p').map((p) => p.innerText), [
          '한글 😀',
          '다음 줄',
        ]);
      },
    );
  }

  test('UTF8 BOM does not become a displayed character', () async {
    final result = await preparer.prepare(
      book: await source([0xef, 0xbb, 0xbf, ...utf8.encode('본문')]),
    );
    final zip = ZipDecoder().decodeBytes(
      await File(result.filePath).readAsBytes(),
    );
    final chapter = XmlDocument.parse(
      utf8.decode(zip.findFile('EPUB/section-00000.xhtml')!.content),
    );
    expect(chapter.findAllElements('p').single.innerText, '본문');
  });

  test(
    'legacy encodings and malformed UTF16 fail without replacement characters',
    () async {
      for (final invalid in <List<int>>[
        [0xb0, 0xa1],
        [0xff, 0xfe, 0x00, 0xd8],
        [0xfe, 0xff, 0x31],
      ]) {
        final book = await source(invalid);
        await expectLater(
          preparer.prepare(book: book),
          throwsA(preparationError('unsupported_encoding')),
        );
      }
      expect(await Directory('${temporary.path}/owned').exists(), isFalse);
    },
  );

  test(
    'BOM-less UTF16 and XML-illegal control characters are not silently accepted',
    () async {
      final book = await source([0x41, 0, 0x42, 0]);
      await expectLater(
        preparer.prepare(book: book),
        throwsA(preparationError('invalid_text')),
      );
    },
  );

  test(
    'long lines create bounded spine sections with valid surrogate pairs',
    () async {
      final content = '${'가' * 31999}😀${'나' * 40000}';
      final result = await preparer.prepare(
        book: await source(utf8.encode(content)),
      );
      final zip = ZipDecoder().decodeBytes(
        await File(result.filePath).readAsBytes(),
      );
      final chapters = zip.files.where(
        (file) => file.name.startsWith('EPUB/section-'),
      );
      expect(chapters.length, greaterThan(1));
      final reconstructed = chapters
          .map(
            (file) => XmlDocument.parse(
              utf8.decode(file.content),
            ).findAllElements('p').map((p) => p.innerText).join(),
          )
          .join();
      expect(reconstructed, content);
    },
  );

  test(
    'original EPUB bytes and resources are copied without flattening',
    () async {
      final bytes = _epub(
        extra: {
          'EPUB/style.css': 'p {color: #123456;}',
          'EPUB/image.png': 'image bytes',
        },
      );
      final book = await source(bytes, extension: 'epub');
      final result = await preparer.prepare(book: book);
      expect(await File(result.filePath).readAsBytes(), bytes);
      expect(result.filePath, isNot(book.localPath));
    },
  );

  test(
    'invalid EPUB, fixed layout, DRM and unsafe archive paths fail explicitly',
    () async {
      final cases = <(List<int>, String)>[
        ([1, 2, 3], 'invalid_epub'),
        (
          _epub(
            metadata: '<meta property="rendition:layout">pre-paginated</meta>',
          ),
          'fixed_layout',
        ),
        (_epub(extra: {'META-INF/license.lcpl': '{}'}), 'drm'),
        (_epub(extra: {'../outside.txt': 'bad'}), 'invalid_epub'),
        (_epub(extra: {'/absolute.txt': 'bad'}), 'invalid_epub'),
        (_epub(extra: {'folder\\outside.txt': 'bad'}), 'invalid_epub'),
      ];
      for (final (bytes, code) in cases) {
        await expectLater(
          preparer.prepare(book: await source(bytes, extension: 'epub')),
          throwsA(preparationError(code)),
        );
      }
    },
  );

  test(
    'scripted markup, event handlers, external resources and CSS imports fail',
    () async {
      final cases = [
        _epub(body: '<script>alert(1)</script><p>text</p>'),
        _epub(body: '<p onclick="alert(1)">text</p>'),
        _epub(body: '<img src="https://example.com/image.png"/>'),
        _epub(body: '<a href="javascript:alert(1)">text</a>'),
        _epub(
          body:
              '<style>@import "https://example.com/style.css";</style><p>text</p>',
        ),
        _epub(
          body: '<p style="background:url(https://example.com/x)">text</p>',
        ),
        _epub(body: '<img src="file:/private/image.png"/>'),
        _epub(
          extra: {
            'EPUB/extra.xhtml':
                '<html xmlns="http://www.w3.org/1999/xhtml"><body><script>alert(1)</script></body></html>',
          },
        ),
        _epub(
          extra: {
            'EPUB/extra.css':
                r'p {background:url(h\74tps://example.com/image.png)}',
          },
        ),
      ];
      for (final bytes in cases) {
        await expectLater(
          preparer.prepare(book: await source(bytes, extension: 'epub')),
          throwsA(preparationError('active_content')),
        );
      }
    },
  );

  test(
    'standard font obfuscation is preserved while content encryption is DRM',
    () async {
      const fontPath = 'EPUB/book-font.ttf';
      const encryptionStart =
          '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#"><EncryptionMethod Algorithm="';
      const encryptionEnd =
          '"/><CipherData><CipherReference URI="$fontPath"/></CipherData></EncryptedData></encryption>';
      final bytes = _epub(
        manifest:
            '<item id="font" href="book-font.ttf" media-type="font/ttf"/>',
        extra: {
          fontPath: 'obfuscated font bytes',
          'META-INF/encryption.xml':
              '${encryptionStart}http://www.idpf.org/2008/embedding$encryptionEnd',
        },
      );
      final result = await preparer.prepare(
        book: await source(bytes, extension: 'epub'),
      );
      expect(await File(result.filePath).readAsBytes(), bytes);
      final encrypted = _epub(
        extra: {
          'META-INF/encryption.xml':
              '${encryptionStart}http://www.w3.org/2001/04/xmlenc#aes256-cbc$encryptionEnd',
        },
      );
      await expectLater(
        preparer.prepare(book: await source(encrypted, extension: 'epub')),
        throwsA(preparationError('drm')),
      );
    },
  );

  test(
    'corrupt compressed content is rejected by integrity validation',
    () async {
      final bytes = _epub();
      // The mimetype is deliberately stored: alter its data while preserving CRC.
      final corrupted = Uint8List.fromList(bytes);
      final start = _indexOf(corrupted, utf8.encode('application/epub+zip'));
      expect(start, greaterThanOrEqualTo(0));
      corrupted[start] ^= 1;
      await expectLater(
        preparer.prepare(book: await source(corrupted, extension: 'epub')),
        throwsA(preparationError('invalid_epub')),
      );
    },
  );

  test(
    'publication ID cannot escape storage and missing source is actionable',
    () async {
      final book = await source(utf8.encode('안전한 경로'), id: '../../outside');
      final result = await preparer.prepare(book: book);
      expect(result.publicationId, '../../outside');
      expect(result.filePath.startsWith('${temporary.path}/owned/'), isTrue);
      await File(book.localPath!).delete();
      final missing = Book.localFile(
        id: 'missing',
        title: '',
        author: '',
        description: '',
        localPath: '${temporary.path}/missing.txt',
      );
      await expectLater(
        preparer.prepare(book: missing),
        throwsA(preparationError('missing_source')),
      );
    },
  );
}

Uint8List _epub({
  String body = '<p id="p1">본문</p>',
  String metadata = '',
  String manifest = '',
  Map<String, String> extra = const {},
}) {
  final archive = Archive();
  archive.add(
    ArchiveFile.noCompress('mimetype', 20, utf8.encode('application/epub+zip')),
  );
  archive.add(
    ArchiveFile.string(
      'META-INF/container.xml',
      '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    ),
  );
  archive.add(
    ArchiveFile.string(
      'EPUB/package.opf',
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">test</dc:identifier><dc:title>Test</dc:title><dc:language>ko</dc:language>$metadata</metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>$manifest</manifest><spine><itemref idref="chapter"/></spine></package>',
    ),
  );
  archive.add(
    ArchiveFile.string(
      'EPUB/chapter.xhtml',
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Test</title></head><body>$body</body></html>',
    ),
  );
  for (final entry in extra.entries) {
    archive.add(ArchiveFile.string(entry.key, entry.value));
  }
  return ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2000));
}

int _indexOf(List<int> source, List<int> pattern) {
  for (var i = 0; i <= source.length - pattern.length; i++) {
    if (List.generate(
      pattern.length,
      (index) => source[i + index] == pattern[index],
    ).every((same) => same)) {
      return i;
    }
  }
  return -1;
}
