import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_page.dart';
import 'helpers/catalog_fixture.dart';

Future<void> pumpCatalog(
  WidgetTester tester,
  FakeReaderCatalog catalog, {
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
        home: const ReaderCatalogPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'search includes later server pages and combines author with category',
    (tester) async {
      final catalog = FakeReaderCatalog([
        for (var i = 1; i <= 40; i++) catalogFixture(i),
        catalogFixture(41, title: '가을 에세이', author: '김작가', category: '에세이'),
      ]);
      await pumpCatalog(tester, catalog);
      expect(catalog.calls, ['book:null', 'book:40']);
      await tester.enterText(find.byType(TextField), '김작가');
      await tester.pumpAndSettle();
      expect(find.text('가을 에세이'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '시'));
      await tester.pumpAndSettle();
      expect(find.text('검색 조건에 맞는 도서가 없습니다.'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '에세이'));
      await tester.pumpAndSettle();
      expect(find.text('가을 에세이'), findsOneWidget);
      expect(catalog.calls.length, 2);
    },
  );

  testWidgets('tabs preserve independent search and list scroll positions', (
    tester,
  ) async {
    final catalog = FakeReaderCatalog([
      for (var i = 1; i < 25; i++) catalogFixture(i),
      catalogFixture(30, kind: 'font', title: '학교안심체'),
      catalogFixture(31, kind: 'font', title: '메이플스토리'),
    ]);
    await pumpCatalog(tester, catalog);
    await tester.enterText(find.byType(TextField), '도서');
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('catalog-list-book'));
    await tester.drag(list, const Offset(0, -600));
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(list).controller!;
    final offset = controller.offset;
    expect(offset, greaterThan(0));
    await tester.tap(find.text('글꼴'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '학교');
    await tester.pumpAndSettle();
    expect(find.text('학교안심체'), findsOneWidget);
    expect(find.text('메이플스토리'), findsNothing);
    await tester.tap(find.text('도서'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '도서',
    );
    expect(controller.offset, closeTo(offset, 1));
    await tester.tap(find.text('글꼴'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '학교',
    );
  });

  testWidgets('failed catalog loads show retry and do not claim no results', (
    tester,
  ) async {
    final catalog = FakeReaderCatalog([catalogFixture(1)])..fail = true;
    await pumpCatalog(tester, catalog);
    expect(find.text('연결 실패'), findsOneWidget);
    expect(find.textContaining('아직 공개된'), findsNothing);
    catalog.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('도서 001'), findsOneWidget);
  });

  testWidgets(
    'download continues across tab changes and marks the item installed',
    (tester) async {
      final catalog = FakeReaderCatalog([
        catalogFixture(1),
        catalogFixture(2, kind: 'font'),
      ]);
      await pumpCatalog(tester, catalog);
      catalog.downloadGate = Completer<void>();
      await tester.tap(
        find.byWidgetPredicate((widget) => widget is FilledButton),
      );
      await tester.pump();
      await tester.tap(find.text('글꼴'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((widget) => widget is FilledButton),
            )
            .onPressed,
        isNull,
      );
      catalog.downloadGate!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('도서'));
      await tester.pumpAndSettle();
      expect(find.text('다운로드 완료'), findsOneWidget);
    },
  );

  for (final size in [const Size(280, 350), const Size(320, 700)]) {
    testWidgets('catalog fits $size with large text', (tester) async {
      await pumpCatalog(
        tester,
        FakeReaderCatalog([catalogFixture(1)]),
        size: size,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('catalog cache sorts the complete list and deduplicates ids', () async {
    final a = catalogFixture(1, title: '가을');
    final catalog = FakeReaderCatalog([catalogFixture(2, title: '하늘'), a, a]);
    final container = ProviderContainer(
      overrides: [
        readerCatalogProvider.overrideWithValue(catalog),
        booksProvider.overrideWith((ref) async => []),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(catalog.close);
    final items = await container.read(catalogItemsProvider('book').future);
    expect(items.map((item) => item.title), ['가을', '하늘']);
  });
}
