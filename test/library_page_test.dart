import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/library_reading_state.dart';
import 'package:koofy_reader/features/library/presentation/library_page.dart';
import 'package:koofy_reader/features/library/presentation/widgets/book_tile.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers/catalog_fixture.dart';

final demoBooks = List.generate(
  12,
  (i) => Book.asset(
    id: 'b$i',
    title:
        ['숲의 문장들', '작은 생활', '밤의 도서관', '여행의 온도', '취향의 기록', '푸른 계절'][i % 6] +
        (i < 6 ? '' : ' $i'),
    author: i == 1 ? '김작가' : '쿠피 작가',
    description: '',
    assetPath: 'assets/books/sample_1.txt',
  ),
);
final demoState = {
  'b0': LibraryReadingState(
    progression: .42,
    lastReadAt: DateTime.now(),
    chapterTitle: '3장 · 느리게 걷는 오후',
  ),
  'b1': LibraryReadingState(
    needsMigration: true,
    progression: .18,
    lastReadAt: DateTime(2026, 9, 1),
  ),
};

Future<void> pumpLibrary(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  List<Book>? books,
  List<BookGroup>? groups,
  Future<Map<String, LibraryReadingState>> Function()? states,
  List<ui.DisplayFeature> features = const [],
  Brightness brightness = Brightness.light,
  List<RouteSettings>? routes,
  List<NativeLibraryPosition> Function()? nativePositions,
  bool realCompletion = false,
  List<CatalogItem> catalog = const [],
}) async {
  const captureDirectory = String.fromEnvironment('LIBRARY_CAPTURE_DIR');
  if (captureDirectory.isNotEmpty) {
    await tester.runAsync(() async {
      if (Platform.isMacOS) {
        await ui.loadFontFromList(
          await File(
            '/System/Library/Fonts/AppleSDGothicNeo.ttc',
          ).readAsBytes(),
          fontFamily: 'Roboto',
        );
      }
      final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
      await ui.loadFontFromList(
        icons.buffer.asUint8List(),
        fontFamily: 'MaterialIcons',
      );
    });
  }
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogItemsProvider('book').overrideWith((ref) async => catalog),
        catalogInstalledProvider('book').overrideWith((ref) async => {}),
        catalogItemsProvider('font').overrideWith((ref) async => []),
        catalogInstalledProvider('font').overrideWith((ref) async => {}),
        booksProvider.overrideWith((ref) async => books ?? demoBooks),
        if (groups != null)
          bookGroupsProvider.overrideWith((ref) async => groups),
        if (nativePositions == null)
          libraryReadingStateProvider.overrideWith(
            (ref) => states?.call() ?? Future.value(demoState),
          ),
        if (nativePositions != null) ...[
          nativeLibraryPositionsProvider.overrideWith(
            (ref) async => nativePositions(),
          ),
          legacyReadingProgressProvider.overrideWith((ref) async => {}),
        ],
        if (!realCompletion)
          libraryCompletionProvider.overrideWith((ref) async => {}),
        nativeReaderAvailableProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            displayFeatures: features,
            platformBrightness: brightness,
          ),
          child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
        ),
        home: const LibraryPage(),
        onGenerateRoute: (settings) {
          routes?.add(settings);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => Scaffold(
              appBar: AppBar(title: Text(settings.name!)),
              body: Text(
                settings.arguments is Book
                    ? (settings.arguments as Book).id
                    : '다운로드 화면',
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> capture(WidgetTester tester, String name) async {
  const target = String.fromEnvironment('LIBRARY_CAPTURE_DIR');
  if (target.isEmpty) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(target).create(recursive: true);
    await File('$target/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [390.0, 840.0]) {
    testWidgets(
      'resume uses group cover without changing member book at $width',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync('resume-cover-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2h0sAAAAASUVORK5CYII=',
        );
        final groupFile = File('${directory.path}/group.png')
          ..writeAsBytesSync(png);
        final memberFile = File('${directory.path}/member.png')
          ..writeAsBytesSync(png);
        final group = BookGroup(
          id: 'group_test',
          title: '묶음 제목',
          bookIds: ['b0'],
          coverPath: groupFile.path,
        );
        final routes = <RouteSettings>[];
        await pumpLibrary(
          tester,
          size: Size(width, 900),
          books: [demoBooks.first],
          groups: [group],
          routes: routes,
        );
        await tester.pumpAndSettle();
        final card = find.byKey(const ValueKey('continue-reading-card'));
        final image = tester.widget<Image>(
          find.descendant(of: card, matching: find.byType(Image)),
        );
        expect(
          (image.image as ResizeImage).imageProvider,
          FileImage(groupFile),
        );
        expect(
          find.descendant(of: card, matching: find.text(demoBooks.first.title)),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, '이어 읽기'));
        await tester.pumpAndSettle();
        expect(routes.single.name, AppRoutes.nativeReader);
        expect(identical(routes.single.arguments, demoBooks.first), isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpLibrary(
          tester,
          size: Size(width, 900),
          books: [demoBooks.first.withCoverPath(memberFile.path)],
          groups: [group],
        );
        await tester.pumpAndSettle();
        final ownImage = tester.widget<Image>(
          find.descendant(of: card, matching: find.byType(Image)),
        );
        expect(
          (ownImage.image as ResizeImage).imageProvider,
          FileImage(memberFile),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('phone exposes a named download button and persistent search', (
    tester,
  ) async {
    final routes = <RouteSettings>[];
    await pumpLibrary(tester, routes: routes);
    expect(find.byTooltip('서재 검색'), findsNothing);
    expect(find.byTooltip('책 · 글꼴 다운로드'), findsNothing);
    expect(find.widgetWithText(TextField, '내 서재에서 책 검색'), findsOneWidget);
    await tester.ensureVisible(find.text('도서·글꼴 다운로드'));
    await tester.tap(find.text('도서·글꼴 다운로드'));
    await tester.pumpAndSettle();
    expect(routes.single.name, AppRoutes.catalog);
  });
  testWidgets(
    'wide menus are exclusive and preserve catalog tab query and scroll',
    (tester) async {
      await pumpLibrary(
        tester,
        size: const Size(840, 900),
        catalog: [for (var i = 0; i < 12; i++) catalogFixture(i)],
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('continue-reading-card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('catalog-search-book')), findsNothing);
      expect(find.text('내 서재'), findsNothing);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('KOOFY')),
        findsNothing,
      );
      expect(find.text('이어 읽기'), findsOneWidget);
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
      await capture(tester, 'reading-expanded');
      await tester.tap(find.byKey(const ValueKey('toggle-downloads')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('continue-reading-card')), findsNothing);
      final header = find.byKey(const ValueKey('expand-reading'));
      final before = tester.getRect(header);
      final shelf = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('library-scroll')),
          )
          .controller!;
      await tester.enterText(
        find.byKey(const ValueKey('catalog-search-book')),
        '도서',
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const PageStorageKey('catalog-list-book'));
      await tester.drag(list, const Offset(0, -350));
      await tester.pumpAndSettle();
      final controller = tester.widget<ListView>(list).controller!;
      final offset = controller.offset;
      expect(offset, greaterThan(0));
      expect(shelf.offset, 0);
      expect(tester.getRect(header), before);
      await capture(tester, 'downloads-expanded');
      await tester.tap(find.text('글꼴'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('catalog-search-font')),
        '학교',
      );
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('continue-reading-card')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('catalog-search-font')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('toggle-downloads')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('catalog-search-font')),
            )
            .controller!
            .text,
        '학교',
      );
      await tester.tap(find.text('도서'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('catalog-search-book')),
            )
            .controller!
            .text,
        '도서',
      );
      expect(tester.widget<ListView>(list).controller, same(controller));
      expect(controller.offset, closeTo(offset, 1));
      await tester.tap(find.byKey(const ValueKey('toggle-downloads')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('continue-reading-card')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long reading card grows with content and sidebar scrolls as a whole',
    (tester) async {
      final book = Book.asset(
        id: 'long',
        title: '긴 제목을 생략하지 않고 자연스럽게 보여 주는 책입니다 ' * 3,
        author: '쿠피 작가',
        description: '',
        assetPath: 'sample.txt',
      );
      final chapter = '장 이름도 내용에 맞게 자연스럽게 표시합니다 ' * 3;
      await pumpLibrary(
        tester,
        size: const Size(840, 450),
        scale: 2,
        books: [book],
        states: () async => {
          'long': LibraryReadingState(
            progression: .3,
            lastReadAt: DateTime.now(),
            chapterTitle: chapter,
          ),
        },
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('continue-reading-card'));
      final title = find.descendant(of: card, matching: find.text(book.title));
      expect(tester.widget<Text>(title.last).maxLines, isNull);
      expect(tester.widget<Text>(find.text(chapter)).maxLines, isNull);
      final button = find.widgetWithText(FilledButton, '이어 읽기');
      expect(
        tester.getRect(button).bottom,
        lessThan(tester.getRect(card).bottom),
      );
      expect(tester.getSize(card).height, greaterThan(450));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('toggle-downloads')),
      );
      await tester.tap(find.byKey(const ValueKey('toggle-downloads')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('catalog-search-book')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expand-reading')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('returning from reader refreshes committed native progress', (
    tester,
  ) async {
    var ratio = .42;
    await pumpLibrary(
      tester,
      nativePositions: () => [
        NativeLibraryPosition(
          publicationId: 'b0',
          lastOpenedAt: DateTime.now(),
          locatorJson:
              '{"href":"chapter.xhtml","locations":{"totalProgression":$ratio}}',
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('42% 읽음'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, '이어 읽기'));
    await tester.pumpAndSettle();
    ratio = .63;
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('63% 읽음'), findsWidgets);
    expect(find.text('42% 읽음'), findsNothing);
  });
  testWidgets(
    'completion menu persists and can be undone without deleting book',
    (tester) async {
      await pumpLibrary(tester, books: [demoBooks.first], realCompletion: true);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('숲의 문장들 더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('숲의 문장들 더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('완독으로 표시'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('continue-reading-card')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, '완독'));
      await tester.pumpAndSettle();
      expect(find.byType(BookTile), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('숲의 문장들 더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('숲의 문장들 더보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('완독 표시 해제'));
      await tester.pumpAndSettle();
      expect(find.text('0권'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('continue-reading-card')),
        findsOneWidget,
      );
    },
  );
  testWidgets('book menu exposes archived records and has no engine chooser', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.ensureVisible(find.byTooltip('숲의 문장들 더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('숲의 문장들 더보기'));
    await tester.pumpAndSettle();
    expect(find.text('기존 리더로 읽기'), findsNothing);
    expect(find.text('새 리더로 읽기'), findsNothing);
    expect(find.text('이전 버전의 독서 기록'), findsOneWidget);
    expect(find.text('표지 이미지 등록'), findsOneWidget);
    expect(find.text('표지 초기화'), findsNothing);
  });
  testWidgets('book with an image offers cover replacement and reset', (
    tester,
  ) async {
    await pumpLibrary(
      tester,
      books: [demoBooks.first.withCoverPath('/missing-cover.png')],
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('숲의 문장들 더보기'));
    await tester.tap(find.byTooltip('숲의 문장들 더보기'));
    await tester.pumpAndSettle();
    expect(find.text('표지 이미지 변경'), findsOneWidget);
    expect(find.text('표지 초기화'), findsOneWidget);
    expect(find.text('표지 이미지 등록'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('phone shows continuation and opens the matching native route', (
    tester,
  ) async {
    final routes = <RouteSettings>[];
    await pumpLibrary(tester, routes: routes);
    expect(find.byKey(const ValueKey('continue-reading-card')), findsOneWidget);
    expect(find.byTooltip('새 리더로 읽기 (미리 보기)'), findsNothing);
    await capture(tester, 'phone');
    await tester.tap(find.widgetWithText(FilledButton, '이어 읽기'));
    await tester.pumpAndSettle();
    expect(routes.single.name, AppRoutes.nativeReader);
    expect((routes.single.arguments as Book).id, 'b0');
  });
  testWidgets('legacy continuation always enters Readium migration flow', (
    tester,
  ) async {
    final routes = <RouteSettings>[];
    await pumpLibrary(
      tester,
      routes: routes,
      states: () async => {'b1': demoState['b1']!},
    );
    await tester.tap(find.widgetWithText(FilledButton, '이어 읽기'));
    await tester.pumpAndSettle();
    expect(routes.single.name, AppRoutes.nativeReader);
  });
  testWidgets('new book opens native reader and no read record is invented', (
    tester,
  ) async {
    final routes = <RouteSettings>[];
    await pumpLibrary(
      tester,
      books: [demoBooks.first],
      states: () async => {},
      routes: routes,
    );
    expect(find.byKey(const ValueKey('continue-reading-card')), findsNothing);
    await tester.tap(find.byType(BookCover));
    await tester.pumpAndSettle();
    expect(routes.single.name, AppRoutes.nativeReader);
  });
  testWidgets('empty library has one clear import action', (tester) async {
    await pumpLibrary(tester, books: [], states: () async => {});
    expect(find.text('첫 책 가져오기'), findsOneWidget);
    expect(find.byType(BookTile), findsNothing);
    await capture(tester, 'empty');
  });
  testWidgets(
    'search matches author and filters combine without losing query',
    (tester) async {
      await pumpLibrary(tester);
      expect(find.byTooltip('서재 검색'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '김작가');
      await tester.pumpAndSettle();
      expect(find.text('1권'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '읽을 책'));
      await tester.pumpAndSettle();
      expect(find.text('0권'), findsOneWidget);
      expect(find.text('조건에 맞는 책이 없어요.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '김작가',
      );
    },
  );
  testWidgets('unknown reading state does not launch at a guessed location', (
    tester,
  ) async {
    final pending = Completer<Map<String, LibraryReadingState>>();
    await pumpLibrary(tester, states: () => pending.future);
    for (final tile in tester.widgetList<BookTile>(find.byType(BookTile))) {
      expect(tile.onTap, isNull);
    }
    pending.complete(demoState);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '이어 읽기'))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('reading failure preserves shelf with retry action', (
    tester,
  ) async {
    await pumpLibrary(
      tester,
      states: () => Future.error(StateError('database unavailable')),
    );
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.byType(BookTile), findsWidgets);
    expect(find.textContaining('database unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(840, 900),
  ]) {
    testWidgets('layout fits $size with large text', (tester) async {
      await pumpLibrary(tester, size: size, scale: 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const PageStorageKey('library-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(840, 900),
  ]) {
    testWidgets('six books occupy two rows of three at $size', (tester) async {
      await pumpLibrary(tester, size: size, books: demoBooks.take(6).toList());
      await tester.pumpAndSettle();
      // A permanently visible search field can put the grid beyond the lazy
      // viewport on small phones; scroll until its first row is built.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('b0')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('library-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final tiles = find.byType(BookTile);
      expect(tiles, findsNWidgets(6));
      final rects = [for (var i = 0; i < 6; i++) tester.getRect(tiles.at(i))];
      for (var i = 1; i < 3; i++) {
        expect(rects[i].top, closeTo(rects[0].top, .1));
        expect(rects[i].left, greaterThan(rects[i - 1].right));
        expect(rects[i + 3].top, closeTo(rects[3].top, .1));
      }
      final coverRects = [
        for (var i = 0; i < 3; i++)
          tester.getRect(
            find.descendant(of: tiles.at(i), matching: find.byType(BookCover)),
          ),
      ];
      expect(coverRects[1].height, closeTo(coverRects[0].height, .1));
      expect(coverRects[2].height, closeTo(coverRects[0].height, .1));
      expect(rects[3].top, greaterThan(rects[0].bottom));
      for (var i = 0; i < 3; i++) {
        expect(rects[i + 3].left, closeTo(rects[i].left, .1));
      }
      expect(tester.takeException(), isNull);
      await capture(tester, 'three-columns-${size.width.toInt()}');
    });
  }
  testWidgets(
    'wide screen puts continuation beside books and respects vertical hinge',
    (tester) async {
      const hinge = ui.DisplayFeature(
        bounds: Rect.fromLTWH(390, 0, 28, 900),
        type: ui.DisplayFeatureType.hinge,
        state: ui.DisplayFeatureState.postureFlat,
      );
      await pumpLibrary(tester, size: const Size(840, 900), features: [hinge]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-two-pane')), findsOneWidget);
      final card = tester.getRect(
        find.byKey(const ValueKey('continue-reading-card')),
      );
      expect(card.right, lessThanOrEqualTo(hinge.bounds.left));
      for (final element in find.byType(BookTile).evaluate()) {
        expect(
          tester.getRect(find.byWidget(element.widget)).left,
          greaterThanOrEqualTo(hinge.bounds.right),
        );
      }
      expect(tester.takeException(), isNull);
      await capture(tester, 'foldable');
    },
  );
  testWidgets('horizontal hinge keeps controls on the upper safe screen', (
    tester,
  ) async {
    const hinge = ui.DisplayFeature(
      bounds: Rect.fromLTWH(0, 450, 840, 24),
      type: ui.DisplayFeatureType.hinge,
      state: ui.DisplayFeatureState.postureHalfOpened,
    );
    await pumpLibrary(tester, size: const Size(840, 900), features: [hinge]);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(Scaffold)).bottom,
      lessThanOrEqualTo(450),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('fold and unfold retains filter and scroll controller', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '읽을 책'));
    await tester.tap(find.widgetWithText(ChoiceChip, '읽을 책'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const PageStorageKey('library-scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<CustomScrollView>(
          find.byKey(const PageStorageKey('library-scroll')),
        )
        .controller;
    tester.view.physicalSize = const Size(840, 900);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('library-scroll')),
          )
          .controller,
      same(controller),
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    // The restored book can be below the lazy-built filter header.
    controller!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '읽을 책'));
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '읽을 책'))
          .selected,
      isTrue,
    );
  });
  testWidgets('dark mode renders readable dark surfaces', (tester) async {
    await pumpLibrary(tester, brightness: Brightness.dark);
    final theme = Theme.of(tester.element(find.byType(BookTile).first));
    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    await capture(tester, 'dark');
  });
  testWidgets('tabletop fold without physical gap uses upper screen', (
    tester,
  ) async {
    const fold = ui.DisplayFeature(
      bounds: Rect.fromLTWH(0, 450, 840, 0),
      type: ui.DisplayFeatureType.fold,
      state: ui.DisplayFeatureState.postureHalfOpened,
    );
    await pumpLibrary(tester, size: const Size(840, 900), features: [fold]);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(Scaffold)).bottom,
      lessThanOrEqualTo(450),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty foldable keeps onboarding to one side of hinge', (
    tester,
  ) async {
    const hinge = ui.DisplayFeature(
      bounds: Rect.fromLTWH(390, 0, 28, 900),
      type: ui.DisplayFeatureType.hinge,
      state: ui.DisplayFeatureState.postureFlat,
    );
    await pumpLibrary(
      tester,
      size: const Size(840, 900),
      features: [hinge],
      books: [],
      states: () async => {},
    );
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('기기에 있는 EPUB · TXT 파일을 가져오세요.')).right,
      lessThan(390),
    );
    expect(tester.getRect(find.text('첫 책 가져오기')).right, lessThan(390));
    expect(tester.takeException(), isNull);
  });
  testWidgets('changing grid width keeps the visible book near the top', (
    tester,
  ) async {
    final manyBooks = List.generate(
      80,
      (i) => Book.asset(
        id: 'scroll-$i',
        title: '책 ${i.toString().padLeft(3, '0')}',
        author: '작가',
        description: '',
        assetPath: 'sample.txt',
      ),
    );
    await pumpLibrary(tester, books: manyBooks, states: () async => {});
    await tester.pumpAndSettle();
    final controller = tester
        .widget<CustomScrollView>(
          find.byKey(const PageStorageKey('library-scroll')),
        )
        .controller!;
    controller.jumpTo(1800);
    await tester.pumpAndSettle();
    String topBook() {
      final viewport = tester.getRect(
        find.byKey(const PageStorageKey('library-scroll')),
      );
      final tiles =
          find.byType(BookTile).evaluate().where((e) {
            final rect = tester.getRect(find.byWidget(e.widget));
            return rect.bottom > viewport.top && rect.top < viewport.bottom;
          }).toList()..sort(
            (a, b) => tester
                .getRect(find.byWidget(a.widget))
                .top
                .compareTo(tester.getRect(find.byWidget(b.widget)).top),
          );
      return (tiles.first.widget as BookTile).book.id;
    }

    final before = topBook();
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    final original = find.byKey(ValueKey(before));
    expect(original, findsOneWidget);
    expect(
      tester.getRect(original).bottom,
      greaterThan(
        tester.getRect(find.byKey(const PageStorageKey('library-scroll'))).top,
      ),
    );
    expect(tester.getRect(original).top, lessThan(350));
    expect(tester.takeException(), isNull);
  });
}
