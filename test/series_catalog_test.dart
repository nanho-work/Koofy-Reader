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
      expect(find.text('연재 중'), findsOneWidget);
      expect(find.text('1화 · 이야기 1'), findsNothing);
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
      await tester.tap(find.text('출처·이용 조건'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('출처·이용 조건'));
      await tester.pumpAndSettle();
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
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == '40화 · 이야기 40',
        ),
        findsOneWidget,
      );
      expect(find.text('100화 · 이야기 100'), findsNothing);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == '40화 · 이야기 40',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('book-download-${episodes[39].id}')),
      );
      await tester.pumpAndSettle();
      expect(catalog.installed, contains(catalogItemKey(episodes[39])));
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == '40화 · 이야기 40',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(ValueKey('book-download-${episodes[39].id}')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('series-back-to-books')));
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
      await tester.tap(find.byKey(const ValueKey('series-back-to-books')));
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

  for (final size in [
    const Size(951, 669),
    const Size(700, 540),
    const Size(600, 900),
    const Size(674, 841),
    const Size(820, 1180),
    const Size(1180, 820),
  ]) {
    testWidgets('series information and episodes split at $size', (
      tester,
    ) async {
      final series = catalogFixture(
        200,
        kind: 'series',
        title: '연재 작품',
        episodeCount: 20,
      );
      await pumpSeries(
        tester,
        FakeReaderCatalog([
          series,
          for (var i = 1; i <= 20; i++)
            catalogFixture(
              i,
              title: '제목 $i',
              seriesId: series.id,
              episodeNumber: i,
            ),
        ]),
        size: size,
        initialQuery: series.title,
      );
      final info = find.byKey(const PageStorageKey('series-information-wide'));
      final search = find.byKey(const ValueKey('series-episode-search'));
      expect(tester.getRect(info).right, lessThan(tester.getRect(search).left));
      expect(find.text('1화 · 제목 1'), findsOneWidget);
      final before = tester.getTopLeft(info);
      await tester.drag(
        find.byKey(ValueKey('series-episodes-${series.id}')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(info), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'license can reopen and survive a layout change without storage collision',
    (tester) async {
      final series = catalogFixture(200, kind: 'series', title: '작품');
      await pumpSeries(
        tester,
        FakeReaderCatalog([series]),
        size: const Size(951, 669),
        initialQuery: series.title,
      );
      final tile = find.byKey(
        PageStorageKey('series-source-license-${series.id}'),
      );
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(tile);
        await tester.tap(find.text('출처·이용 조건'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectableText), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('출처·이용 조건'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('출처·이용 조건'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(tile);
      await tester.tap(find.text('출처·이용 조건'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      await pumpSeries(
        tester,
        catalog,
        size: size,
        scale: 2,
        initialQuery: series.title,
      );
      expect(find.byType(ReaderSeriesPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
