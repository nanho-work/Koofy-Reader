import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader/features/native_reader/data/text_publication_map.dart';
import 'package:xml/xml.dart';

void main() {
  late Directory directory;
  late ReadingPublicationPreparer preparer;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('koofy-chapters-');
    preparer = ReadingPublicationPreparer(
      storageDirectory: Directory('${directory.path}/owned'),
    );
  });
  tearDown(() => directory.delete(recursive: true));

  Future<PreparedReadingPublication> prepare(String text) async {
    final file = File('${directory.path}/book.txt');
    await file.writeAsString(text);
    return preparer.prepare(
      book: Book.localFile(
        id: 'book',
        title: '책',
        author: '작가',
        description: '',
        localPath: file.path,
      ),
    );
  }

  Future<Archive> archive(PreparedReadingPublication book) async =>
      ZipDecoder().decodeBytes(await File(book.filePath).readAsBytes());
  XmlDocument document(Archive zip, String path) =>
      XmlDocument.parse(utf8.decode(zip.findFile(path)!.content));

  test(
    'chapter titles, line breaks and fragment TOC survive TXT conversion',
    () async {
      const text =
          '\n  \n[장] 봄 & <햇살>  \r\n첫 줄\r\n\r\n  둘째 줄 😀\r\n[장]\t제2화\r\n다음 이야기';
      final result = await prepare(text);
      final zip = await archive(result);
      final page = document(zip, 'EPUB/section-00000.xhtml');
      expect(page.findAllElements('h2').map((e) => e.innerText), [
        '봄 & <햇살>',
        '제2화',
      ]);
      expect(page.findAllElements('p').map((e) => e.innerText), [
        '첫 줄',
        '',
        '  둘째 줄 😀',
        '다음 이야기',
      ]);
      expect(
        page.findAllElements('body').single.innerText,
        isNot(contains('[장]')),
      );
      final links = document(
        zip,
        'EPUB/nav.xhtml',
      ).findAllElements('a').toList();
      expect(links.map((e) => e.innerText), ['봄 & <햇살>', '제2화']);
      // Short poems share a resource so column breaks can fill both spread leaves.
      expect(
        document(zip, 'EPUB/package.opf').findAllElements('itemref'),
        hasLength(1),
      );
      for (final link in links) {
        final href = link.getAttribute('href')!.split('#');
        final target = document(zip, 'EPUB/${href.first}').descendants
            .whereType<XmlElement>()
            .singleWhere((e) => e.getAttribute('id') == href.last);
        expect(target.innerText, link.innerText);
      }
      final css = utf8.decode(zip.findFile('EPUB/style.css')!.content);
      expect(css, contains('break-before: column'));
      expect(css, contains('chapter:first-child'));
      final validated = await preparer.prepare(
        book: Book.localFile(
          id: 'generated-epub',
          title: '책',
          author: '작가',
          description: '',
          localPath: result.filePath,
        ),
      );
      expect(validated.contentRevision, result.contentRevision);
    },
  );

  test('bare, inline, indented and unspaced markers stay literal', () async {
    const text = '[장]\n[장]   \n문장 속 [장] 제1화\n [장] 예시\n[장]제1화\n[작품] 제1화';
    final result = await prepare(text);
    expect(result.textMap!.hasChapters, isFalse);
    final zip = await archive(result);
    expect(
      document(
        zip,
        'EPUB/section-00000.xhtml',
      ).findAllElements('p').map((e) => e.innerText).join('\n'),
      text,
    );
  });

  test(
    'preamble appears once and chunk boundaries do not add fake chapters',
    () async {
      final text =
          '머리말 본문\n[장] 긴 이야기\n${'가' * 31999}😀${'나' * 40000}\n[장] 끝 이야기\n끝';
      final result = await prepare(text);
      final zip = await archive(result);
      final links = document(
        zip,
        'EPUB/nav.xhtml',
      ).findAllElements('a').toList();
      expect(links.map((e) => e.innerText), ['머리말', '긴 이야기', '끝 이야기']);
      expect(
        document(zip, 'EPUB/package.opf').findAllElements('itemref').length,
        greaterThan(1),
      );
      expect(
        document(
          zip,
          'EPUB/section-00000.xhtml',
        ).findAllElements('p').any((p) => p.innerText.startsWith('가')),
        isTrue,
        reason:
            'A long first body line must not strand its title in a separate resource.',
      );
      final lines = zip.files
          .where((f) => f.name.startsWith('EPUB/section-'))
          .expand(
            (f) =>
                XmlDocument.parse(utf8.decode(f.content)).findAllElements('p'),
          )
          .map((p) => p.innerText)
          .join();
      expect(lines, '머리말 본문${'가' * 31999}😀${'나' * 40000}끝');
      for (final link in links.skip(1)) {
        final href = link.getAttribute('href')!.split('#');
        expect(
          document(zip, 'EPUB/${href.first}')
              .findAllElements('h2')
              .singleWhere((e) => e.getAttribute('id') == href.last)
              .innerText,
          link.innerText,
        );
      }
    },
  );

  test(
    'source offsets resolve after hidden marker prefixes, whitespace and emoji',
    () async {
      final text = '\n[장] [장]이라는 제목\n시 본문\n[장] 😀 두 번째\n${'가' * 32001}\n마지막';
      final result = await prepare(text);
      final zip = await archive(result);
      for (final offset in [
        0,
        1,
        4,
        text.indexOf('시 본문'),
        text.indexOf('😀'),
        text.indexOf('😀') + 1,
        text.indexOf('마지막'),
      ]) {
        final locator = jsonDecode(result.textMap!.locatorAt(offset)!);
        final point = locator['locations']['koofyText'];
        final id = (point['cssSelector'] as String).substring(1);
        final element = document(zip, locator['href']).descendants
            .whereType<XmlElement>()
            .singleWhere((e) => e.getAttribute('id') == id);
        final highlight = locator['text']['highlight'] as String;
        final at = point['charOffset'] as int;
        expect(
          element.innerText.substring(at, at + highlight.length),
          highlight,
        );
        expect(highlight.runes, hasLength(1));
      }
      final map = TextPublicationMap('[장] [장]이라는 제목');
      expect(map.paragraphs.single.offset, 4);
    },
  );

  test(
    'TXT without chapter markers keeps the exact previous EPUB revision',
    () async {
      final fixtures = {
        '첫 문장 & <본문>\n\n  두 번째 😀\n마지막':
            'cece30750d8970873b9cc744915f5d005b86c4c26b596e10e24e06ec145f04f8',
        '${'가' * 31999}😀${'나' * 40000}':
            '29e92b0b12f4aa8e7940c23def35f71be54368855e4daad0f3d9a97eba892a27',
      };
      for (final fixture in fixtures.entries) {
        expect(
          (await prepare(fixture.key)).contentRevision,
          'epub-sha256:${fixture.value}',
        );
      }
    },
  );
}
