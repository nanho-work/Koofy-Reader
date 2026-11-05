import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/native_reader/application/next_reading.dart';
import 'helpers/catalog_fixture.dart';

Book local(String id) => Book.asset(
  id: id,
  title: 'same title',
  author: '',
  description: '',
  assetPath: '$id.txt',
);
Book downloaded(CatalogItem item, String path) => Book.localFile(
  id: item.bookId,
  title: item.title,
  author: '',
  description: '',
  localPath: path,
  catalogMetadata: item.json,
);
void main() {
  test(
    'personal collections use explicit order; no title guesses or missing-file skips',
    () async {
      final a = local('a'), b = local('b'), c = local('c');
      final group = BookGroup(
        id: 'group_test',
        title: 'group',
        bookIds: ['a', 'b', 'c'],
      );
      expect(
        (await NextReadingResolver.local(a, [a, b, c], [group])).book?.id,
        'b',
      );
      final missing = await NextReadingResolver.local(a, [a, c], [group]);
      expect(missing.kind, NextReadingKind.completed);
      expect(missing.groupEnd, true);
      expect(
        (await NextReadingResolver.local(c, [a, b, c], [group])).kind,
        NextReadingKind.completed,
      );
      expect(
        (await NextReadingResolver.local(a, [a, b], [])).kind,
        NextReadingKind.completed,
      );
    },
  );
  test(
    'catalog sequence is not replaced by a partial automatic monthly group',
    () async {
      final series = catalogFixture(10, kind: 'series');
      final first = catalogFixture(11, seriesId: series.id, episodeNumber: 1);
      final next = catalogFixture(12, seriesId: series.id, episodeNumber: 2);
      final unrelated = catalogFixture(
        13,
        seriesId: 'b' * 32,
        episodeNumber: 2,
      );
      final catalog = FakeReaderCatalog([series, first, next, unrelated]);
      addTearDown(catalog.close);
      final current = downloaded(first, '/unused');
      final result = await NextReadingResolver(catalog).resolve(
        current,
        [current, local('other')],
        [
          BookGroup(
            id: 'group_monthly_${series.id}',
            title: 'custom',
            bookIds: [current.id, 'other'],
          ),
        ],
      );
      expect(result.kind, NextReadingKind.download);
      expect(result.item?.id, next.id);
    },
  );
  test(
    'a personal collection explicitly overrides catalog order without a network',
    () async {
      final first = catalogFixture(101, seriesId: 'a' * 32, episodeNumber: 1);
      final current = downloaded(first, '/unused');
      final manual = local('manual-next');
      final catalog = FakeReaderCatalog([])..fail = true;
      addTearDown(catalog.close);
      final group = BookGroup(
        id: 'group_personal',
        title: 'my order',
        bookIds: [current.id, manual.id],
      );
      expect(
        (await NextReadingResolver(
          catalog,
        ).resolve(current, [current, manual], [group])).book,
        manual,
      );
      expect(catalog.calls, isEmpty);
    },
  );
  test(
    'upcoming content is never downloaded; ongoing/completed are distinct',
    () async {
      final series = catalogFixture(20, kind: 'series');
      final first = catalogFixture(21, seriesId: series.id, episodeNumber: 1);
      final later = catalogFixture(22, seriesId: series.id, episodeNumber: 2);
      final upcoming = CatalogItem.fromJson({
        ...later.json,
        'upcoming': true,
        'assets': {'cover': later.json['assets']['cover']},
        'releaseAt': '2026-12-01T09:00:00+09:00',
      });
      for (final status in ['ongoing', 'completed']) {
        final parent = CatalogItem.fromJson({
          ...series.json,
          'seriesStatus': status,
        });
        final catalog = FakeReaderCatalog([parent, first]);
        addTearDown(catalog.close);
        final current = downloaded(first, '/unused');
        expect(
          (await NextReadingResolver(
            catalog,
          ).resolve(current, [current], [])).kind,
          status == 'completed'
              ? NextReadingKind.completed
              : NextReadingKind.waiting,
        );
      }
      final catalog = FakeReaderCatalog([series, first, upcoming]);
      addTearDown(catalog.close);
      expect(
        (await NextReadingResolver(
          catalog,
        ).resolve(downloaded(first, '/unused'), [], [])).kind,
        NextReadingKind.upcoming,
      );
      expect(catalog.installed, isEmpty);
    },
  );
  test(
    'an exact already-downloaded successor works offline and survives serialization',
    () async {
      final directory = await Directory.systemTemp.createTemp('next-reading-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/next.txt',
      ).writeAsString('next');
      final series = catalogFixture(30, kind: 'series');
      final first = catalogFixture(31, seriesId: series.id, episodeNumber: 1);
      final second = catalogFixture(32, seriesId: series.id, episodeNumber: 2);
      final current = downloaded(first, '/unused');
      final next = Book.fromJson(downloaded(second, file.path).toJson())!;
      expect(next.catalogMetadata?['seriesId'], series.id);
      expect(
        next.withCoverPath('changed').catalogMetadata,
        next.catalogMetadata,
      );
      final catalog = FakeReaderCatalog([])..fail = true;
      addTearDown(catalog.close);
      final result = await NextReadingResolver(
        catalog,
      ).resolve(current, [current, next], []);
      expect(result.kind, NextReadingKind.local);
      expect(result.book?.id, next.id);
      expect(catalog.calls, isEmpty);
      await file.delete();
      await expectLater(
        NextReadingResolver(catalog).resolve(current, [current, next], []),
        throwsA(isA<CatalogException>()),
      );
    },
  );
}
