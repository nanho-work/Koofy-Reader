import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_page.dart';
import 'helpers/catalog_fixture.dart';
import 'package:koofy_reader/features/catalog/presentation/font_catalog_row.dart';

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
            .widget<IconButton>(
              find.byKey(ValueKey('font-download-${catalog.items.last.id}')),
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

  testWidgets('fonts use compact name and icon rows with details on name tap', (
    tester,
  ) async {
    final item = catalogFixture(1, kind: 'font', title: '메이플스토리');
    final catalog = FakeReaderCatalog([
      item,
      catalogFixture(2, kind: 'font', title: '학교안심체'),
    ]);
    await pumpCatalog(tester, catalog);
    await tester.tap(find.text('글꼴'));
    await tester.pumpAndSettle();
    expect(find.byType(FontCatalogRow), findsNWidgets(2));
    expect(tester.getSize(find.byType(FontCatalogRow).first).height, 56);
    expect(find.byType(Card), findsNothing);
    expect(find.text('다운로드'), findsNothing);
    expect(find.byTooltip('메이플스토리 다운로드'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('메이플스토리, 글꼴 정보'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    await tester.tap(find.text('메이플스토리'));
    await tester.pumpAndSettle();
    expect(find.text('출처·이용 조건'), findsOneWidget);
    expect(find.text(item.license), findsOneWidget);
    expect(find.text(item.source), findsOneWidget);
    expect(catalog.installed, isEmpty);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    catalog.downloadGate = Completer<void>();
    await tester.tap(find.byTooltip('메이플스토리 다운로드'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    catalog.downloadGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byTooltip('메이플스토리 다운로드 완료'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsWidgets);
    expect(find.text('다운로드 완료'), findsNothing);
  });

  testWidgets(
    'preview image uses theme tint and failed previews keep searchable names',
    (tester) async {
      final item = catalogFixture(1, kind: 'font', title: '글꼴 미리보기');
      final catalog = FakeReaderCatalog([item]);
      catalog.previews[item.id] = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2h0sAAAAASUVORK5CYII=',
        ),
      );
      await pumpCatalog(tester, catalog);
      await tester.tap(find.text('글꼴'));
      await tester.pumpAndSettle();
      final preview = tester.widget<Image>(find.byType(Image));
      expect(preview.colorBlendMode, BlendMode.srcIn);
      expect(
        preview.color,
        Theme.of(tester.element(find.byType(Image))).colorScheme.onSurface,
      );
      expect(catalog.installed, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('font preview failure falls back to a one-line name', (
    tester,
  ) async {
    final catalog = FakeReaderCatalog([
      catalogFixture(1, kind: 'font', title: '미리보기 없는 글꼴'),
    ])..previewFails = true;
    await pumpCatalog(tester, catalog, size: const Size(280, 450), scale: 2);
    await tester.tap(find.text('글꼴'));
    await tester.pumpAndSettle();
    expect(find.text('미리보기 없는 글꼴'), findsOneWidget);
    expect(tester.widget<Text>(find.text('미리보기 없는 글꼴')).maxLines, 1);
    expect(find.byTooltip('미리보기 없는 글꼴 다운로드'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
