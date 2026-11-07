import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/monthly_koofy_section.dart';
import 'helpers/catalog_fixture.dart';

Book savedEpisode(int id, int number, String seriesId, {String? month}) {
  final item = catalogFixture(id, seriesId: seriesId, episodeNumber: number);
  return Book.localFile(
    id: item.bookId,
    title: item.title,
    author: '',
    description: '',
    localPath: '/test/${item.bookId}.txt',
    catalogMetadata: {
      ...item.json,
      'seriesTitle': month == null ? '같은 제목' : '10월호',
      if (month != null) 'issueMonth': month,
    },
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'monthly groups retain locators and do not take books from user groups',
    () async {
      final repository = BookGroupRepository(SharedPrefsLocalStorage());
      final issue = 'a' * 32;
      final first = savedEpisode(11, 1, issue, month: '2026-10');
      final second = savedEpisode(12, 2, issue, month: '2026-10');
      final third = savedEpisode(13, 3, issue, month: '2026-10');
      await repository.syncCatalogSeries([second], downloadedBookId: second.id);
      await repository.syncCatalogSeries([
        second,
        first,
      ], downloadedBookId: first.id);
      await repository.syncCatalogSeries([
        second,
        first,
      ], downloadedBookId: first.id);
      final group = (await repository.load()).single;
      expect(group.id, 'group_monthly_$issue');
      expect(group.bookIds, [first.id, second.id]);
      expect(group.showMemberCovers, true);
      await repository.create('내가 만든 묶음', [third.id, 'other']);
      await repository.syncCatalogSeries([
        first,
        second,
        third,
      ], downloadedBookId: third.id);
      expect((await repository.load()).first.bookIds, [first.id, second.id]);
    },
  );
  test(
    'existing serials group by work and later downloads respect personal choices',
    () async {
      final repository = BookGroupRepository(SharedPrefsLocalStorage());
      final seriesId = 'a' * 32;
      final first = savedEpisode(21, 1, seriesId);
      final second = savedEpisode(22, 2, seriesId);
      final third = savedEpisode(23, 3, seriesId);
      final fourth = savedEpisode(24, 4, seriesId);
      final otherWork = savedEpisode(25, 1, 'b' * 32);
      await repository.create('개인 묶음', [third.id, 'other']);
      await repository.syncCatalogSeries([second, otherWork, first, third]);

      final groupId = BookGroup.catalogId(seriesId, monthly: false);
      final initial = await repository.load();
      expect(initial.singleWhere((g) => g.id == groupId).bookIds, [
        first.id,
        second.id,
      ]);
      expect(
        initial.singleWhere((g) => g.catalogSeriesId == 'b' * 32).bookIds,
        [otherWork.id],
      );
      expect(initial.singleWhere((g) => g.catalogSeriesId == null).bookIds, [
        third.id,
        'other',
      ]);

      await repository.takeOut(groupId, first.id);
      final books = [first, second, third, fourth, otherWork];
      await repository.syncCatalogSeries(books, downloadedBookId: fourth.id);
      await repository.syncCatalogSeries(books);
      expect(
        (await repository.load()).singleWhere((g) => g.id == groupId).bookIds,
        [second.id, fourth.id],
      );
    },
  );
  for (final expanded in [false, true]) {
    testWidgets('monthly expansion restores saved $expanded on launch', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'monthly_section_expanded_v1': expanded,
      });
      final series = catalogFixture(100, kind: 'series', title: '10월호');
      final episode = catalogFixture(
        101,
        seriesId: series.id,
        episodeNumber: 1,
        title: '첫 이야기',
      );
      final catalog = FakeReaderCatalog([series, episode]);
      addTearDown(catalog.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerCatalogProvider.overrideWithValue(catalog),
            catalogItemsProvider(
              'monthly',
            ).overrideWith((ref) async => [series, episode]),
            libraryReadingStateProvider.overrideWith((ref) async => {}),
          ],
          child: const MaterialApp(home: Scaffold(body: MonthlyKoofySection())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('첫 이야기'), expanded ? findsOneWidget : findsNothing);
      expect(find.text('10월호'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'monthly card survives narrow layout and compilation dismissal persists',
    (tester) async {
      final series = catalogFixture(100, kind: 'series', title: '10월호');
      final episode = catalogFixture(
        101,
        seriesId: series.id,
        episodeNumber: 1,
        title: '첫 이야기',
      );
      final compilation = catalogFixture(102, title: '9월 합본');
      final catalog = FakeReaderCatalog([series, episode, compilation]);
      addTearDown(catalog.close);
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerCatalogProvider.overrideWithValue(catalog),
            catalogItemsProvider(
              'monthly',
            ).overrideWith((ref) async => [series, episode, compilation]),
            libraryReadingStateProvider.overrideWith((ref) async => {}),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: MonthlyKoofySection()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('10월호'), findsOneWidget);
      expect(find.text('첫 이야기'), findsOneWidget);
      expect(find.text('지난 이야기'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('monthly-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('첫 이야기'), findsNothing);
      expect(find.text('NEW'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'monthly_section_expanded_v1',
        ),
        false,
      );
      await tester.tap(find.byKey(const ValueKey('monthly-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('첫 이야기'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          'monthly_section_expanded_v1',
        ),
        true,
      );
      await tester.tap(find.text('확인했어요'));
      await tester.pumpAndSettle();
      expect(find.text('9월 합본'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'monthly_compilations_dismissed_v1',
        ),
        [compilation.id],
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
