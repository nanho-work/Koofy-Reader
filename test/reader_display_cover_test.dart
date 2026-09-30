import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ReadingPublicationPreparer preparer;
  late Book book;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('reader-display-cover-');
    preparer = ReadingPublicationPreparer(
      storageDirectory: Directory('${temp.path}/owned'),
    );
    final file = File('${temp.path}/book.txt');
    await file.writeAsString(
      List.generate(
        80,
        (i) => '본문 $i. 이 문장은 표지를 바꿔도 같은 위치에 남아 있어야 합니다.',
      ).join('\n\n'),
    );
    book = Book.localFile(
      id: 'cover-test',
      title: '표지 테스트',
      author: '쿠피',
      description: '',
      localPath: file.path,
    );
  });
  tearDown(() async => temp.delete(recursive: true));
  Future<Archive> zip(PreparedReadingPublication value) async =>
      ZipDecoder().decodeBytes(await File(value.filePath).readAsBytes());
  final imagePath = File('assets/branding/app_icon.png').absolute.path;

  test(
    'cover occupies a body column without changing body nodes or content identity',
    () async {
      final before = await preparer.prepare(book: book);
      final after = await preparer.prepare(book: book.withCoverPath(imagePath));
      expect(after.hasDisplayCover, true);
      expect(after.contentRevision, before.contentRevision);
      expect(after.filePath, isNot(before.filePath));
      final original = await zip(before), covered = await zip(after);
      expect(covered.files.first.name, 'mimetype');
      expect(covered.files.first.compression, CompressionType.none);
      expect(covered.findFile(readerCoverHref), isNotNull);
      expect(
        XmlDocument.parse(
              utf8.decode(
                covered.findFile('EPUB/section-00000.xhtml')!.content,
              ),
            )
            .findAllElements('body')
            .first
            .children
            .map((n) => n.toXmlString())
            .join(),
        XmlDocument.parse(
              utf8.decode(
                original.findFile('EPUB/section-00000.xhtml')!.content,
              ),
            )
            .findAllElements('body')
            .first
            .children
            .map((n) => n.toXmlString())
            .join(),
      );
      final opf = XmlDocument.parse(
        utf8.decode(covered.findFile('EPUB/package.opf')!.content),
      );
      expect(
        opf.findAllElements('itemref').first.getAttribute('idref'),
        'section-00000',
      );
      final saved = before.textMap!.locatorAt(200);
      expect(after.restoreLocator(saved), saved);
      final without = await preparer.prepare(
        book: book.withCoverPath(imagePath),
        showRegisteredCover: false,
      );
      expect(without.filePath, before.filePath);
      expect(without.restoreLocator(saved), saved);
      final coverLocator = jsonEncode({
        'href': readerCoverHref,
        'type': 'application/xhtml+xml',
        'locations': {'progression': 0},
      });
      expect(
        jsonDecode(after.restoreLocator(coverLocator)!)['href'],
        'EPUB/section-00000.xhtml',
      );
      expect(isReaderCoverLocator(after.restoreLocator(coverLocator)), true);
      expect(without.restoreLocator(coverLocator), isNull);
      // The normal hostile-input validator must also accept our generated file.
      final imported = Book.localFile(
        id: 'roundtrip',
        title: '표지',
        author: '',
        description: '',
        localPath: after.filePath,
      );
      expect(
        (await preparer.prepare(
          book: imported.withCoverPath(imagePath),
        )).filePath,
        isNotEmpty,
      );
      if (const bool.fromEnvironment('GENERATE_COVER_FIXTURE')) {
        final fixture = File('test/fixtures/reader-display-cover.epub');
        await fixture.parent.create(recursive: true);
        await File(after.filePath).copy(fixture.path);
      }
    },
  );
  test('changing or losing cover never changes the body revision', () async {
    final before = await preparer.prepare(book: book.withCoverPath(imagePath));
    final cover = await File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png',
    ).copy('${temp.path}/cover.png');
    final changed = await preparer.prepare(
      book: book.withCoverPath(cover.path),
    );
    expect(changed.contentRevision, before.contentRevision);
    expect(changed.filePath, isNot(before.filePath));
    await cover.delete();
    final missing = await preparer.prepare(
      book: book.withCoverPath(cover.path),
    );
    expect(missing.contentRevision, before.contentRevision);
    expect(missing.hasDisplayCover, false);
    await cover.writeAsString('not an image');
    expect(
      (await preparer.prepare(
        book: book.withCoverPath(cover.path),
      )).hasDisplayCover,
      false,
    );
  });
  test('EPUB2 NCX gets a cover entry without replacing the body', () async {
    final original = await preparer.prepare(book: book);
    final source = await zip(original);
    final out = Archive();
    for (final entry in source.files) {
      if (entry.name == 'EPUB/package.opf') {
        out.add(
          ArchiveFile.string(
            entry.name,
            utf8
                .decode(entry.content)
                .replaceFirst('version="3.0"', 'version="2.0"')
                .replaceFirst('<spine>', '<spine toc="ncx">')
                .replaceFirst(
                  '</manifest>',
                  '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></manifest>',
                ),
          ),
        );
      } else {
        out.add(entry);
      }
    }
    out.add(
      ArchiveFile.string(
        'EPUB/toc.ncx',
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap><navPoint id="first" playOrder="1"><navLabel><text>본문</text></navLabel><content src="section-00000.xhtml"/></navPoint></navMap></ncx>',
      ),
    );
    final epub = File('${temp.path}/epub2.epub');
    await epub.writeAsBytes(ZipEncoder().encodeBytes(out));
    final input = Book.localFile(
      id: 'epub2',
      title: 'EPUB2',
      author: '',
      description: '',
      localPath: epub.path,
      coverPath: imagePath,
    );
    final result = await preparer.prepare(book: input);
    final covered = await zip(result);
    final ncx = XmlDocument.parse(
      utf8.decode(covered.findFile('EPUB/toc.ncx')!.content),
    );
    expect(
      ncx.findAllElements('content').first.getAttribute('src'),
      '../EPUB/section-00000.xhtml',
    );
    expect(ncx.findAllElements('navPoint').last.getAttribute('playOrder'), '2');
    expect(
      XmlDocument.parse(
            utf8.decode(covered.findFile('EPUB/section-00000.xhtml')!.content),
          )
          .findAllElements('body')
          .first
          .children
          .map((n) => n.toXmlString())
          .join(),
      XmlDocument.parse(
            utf8.decode(source.findFile('EPUB/section-00000.xhtml')!.content),
          )
          .findAllElements('body')
          .first
          .children
          .map((n) => n.toXmlString())
          .join(),
    );
  });
  test('original EPUB cover is not duplicated', () async {
    final original = await preparer.prepare(book: book);
    final source = await zip(original);
    for (final semantic in [true, false]) {
      final out = Archive();
      for (final entry in source.files) {
        if (entry.name == 'EPUB/section-00000.xhtml') {
          out.add(
            ArchiveFile.string(
              entry.name,
              '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>표지</title></head><body ${semantic ? 'epub:type="cover"' : ''}><img src="original.png" alt=""/></body></html>',
            ),
          );
        } else if (entry.name == 'EPUB/package.opf') {
          out.add(
            ArchiveFile.string(
              entry.name,
              utf8
                  .decode(entry.content)
                  .replaceFirst(
                    '</manifest>',
                    '<item id="original" href="original.png" media-type="image/png"/></manifest>',
                  ),
            ),
          );
        } else {
          out.add(entry);
        }
      }
      final bytes = await File(imagePath).readAsBytes();
      out.add(ArchiveFile('EPUB/original.png', bytes.length, bytes));
      final epub = File('${temp.path}/original.epub');
      await epub.writeAsBytes(ZipEncoder().encodeBytes(out));
      final input = Book.localFile(
        id: 'epub',
        title: 'EPUB',
        author: '',
        description: '',
        localPath: epub.path,
        coverPath: imagePath,
      );
      final prepared = await preparer.prepare(book: input);
      expect(prepared.hasDisplayCover, false);
      expect((await zip(prepared)).findFile(readerCoverHref), isNull);
    }
  });
}
