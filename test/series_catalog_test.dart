import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_page.dart';
import 'package:koofy_reader/features/catalog/presentation/series_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'helpers/catalog_fixture.dart';

Future<void> pumpSeries(
  WidgetTester tester,
  FakeReaderCatalog catalog, {
  String initialQuery = '',
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(catalog.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        readerCatalogProvider.overrideWithValue(catalog),
        booksProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ReaderCatalogPage(initialBookQuery: initialQuery),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '100 episodes appear as one work, sort numerically and retain downloaded markers',
    (tester) async {
      final series = catalogFixture(
        200,
        kind: 'series',
        title: '인어공주는 파도를 벤다',
        category: '소설',
        episodeCount: 100,
      );
      final episodes = [
        for (var i = 1; i <= 100; i++)
          catalogFixture(
            i,
            title: '이야기 $i',
            seriesId: series.id,
            episodeNumber: i,
          ),
      ];
      final catalog = FakeReaderCatalog([
        series,
        ...episodes,
        catalogFixture(201, title: '단권 도서'),
      ]);
      await pumpSeries(tester, catalog);
      expect(find.byType(SeriesCatalogRow), findsOneWidget);
      expect(find.text('연재 중 · 100화 공개'), findsOneWidget);
      expect(find.text('이야기 1'), findsNothing);
      expect(catalog.calls, ['book:null']);
      await tester.tap(find.byKey(ValueKey('series-open-${series.id}')));
      await tester.pumpAndSettle();
      expect(
        catalog.calls,
        containsAll([
          'series:${series.id}:null',
          'series:${series.id}:40',
          'series:${series.id}:80',
        ]),
      );
      expect(find.text('1화 · 이야기 1'), findsOneWidget);
      expect(find.text('2화 · 이야기 2'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '최신순'));
      await tester.pumpAndSettle();
      expect(find.text('100화 · 이야기 100'), findsOneWidget);
      expect(find.text('99화 · 이야기 99'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('series-episode-search')),
        '이야기 40',
      );
      await tester.pumpAndSettle();
      expect(find.text('40화 · 이야기 40'), findsOneWidget);
      expect(find.text('100화 · 이야기 100'), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('book-download-${episodes[39].id}')),
      );
      await tester.pumpAndSettle();
      expect(catalog.installed, contains(catalogItemKey(episodes[39])));
      expect(
        tester
            .widget<IconButton>(
              find.byKey(ValueKey('book-download-${episodes[39].id}')),
            )
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SeriesCatalogRow), findsOneWidget);
    },
  );

  testWidgets(
    'bundled story continuation opens its exact series and back returns to the catalog',
    (tester) async {
      final series = catalogFixture(200, kind: 'series', title: '인어공주는 파도를 벤다');
      final catalog = FakeReaderCatalog([series]);
      await pumpSeries(tester, catalog, initialQuery: series.title);
      expect(find.byType(ReaderSeriesPage), findsOneWidget);
      expect(find.textContaining('아직 공개된 회차가 없습니다.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderSeriesPage), findsNothing);
      expect(find.byType(SeriesCatalogRow), findsOneWidget);
    },
  );

  testWidgets(
    'episode refresh failure shows retry without claiming an empty work',
    (tester) async {
      final series = catalogFixture(200, kind: 'series', title: '작품');
      final catalog = FakeReaderCatalog([series]);
      await pumpSeries(tester, catalog);
      catalog.fail = true;
      await tester.tap(find.byKey(ValueKey('series-open-${series.id}')));
      await tester.pumpAndSettle();
      expect(find.text('연결 실패'), findsOneWidget);
      expect(find.textContaining('아직 공개된 회차'), findsNothing);
      catalog.fail = false;
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.textContaining('아직 공개된 회차'), findsOneWidget);
    },
  );

  for (final size in [const Size(280, 350), const Size(390, 844)]) {
    testWidgets('series page fits $size with large text', (tester) async {
      final series = catalogFixture(
        200,
        kind: 'series',
        title: '긴 작품 제목과 회차 목록',
        episodeCount: 1,
      );
      final catalog = FakeReaderCatalog([
        series,
        catalogFixture(1, title: '첫 회차', seriesId: series.id, episodeNumber: 1),
      ]);
      await pumpSeries(tester, catalog, size: size, scale: 2, initialQuery: series.title);
      expect(find.byType(ReaderSeriesPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
