import 'helpers/catalog_fixture.dart';
import 'dart:ui' as ui;
import 'package:koofy_reader/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/home/presentation/main_tabs_page.dart';
import 'package:koofy_reader/features/catalog/presentation/monthly_koofy_section.dart';
import 'package:koofy_reader/features/library/presentation/library_page.dart';
import 'library_page_test.dart' show pumpLibrary, capture;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final width in [320.0, 900.0]) {
    testWidgets(
      'editorial home orders new works and separates interviews at $width',
      (tester) async {
        await pumpLibrary(
          tester,
          size: Size(width, 1200),
          rootPage: const MainTabsPage(),
          catalog: [
            catalogFixture(
              1,
              title: 'Older story',
              publishedAt: '2026-10-01T00:00:00Z',
            ),
            catalogFixture(
              2,
              title: 'Newest story',
              publishedAt: '2026-10-30T00:00:00Z',
            ),
            catalogFixture(3, title: 'Interview', category: '사람을 만나다'),
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text('당신의 이야기를 들려주세요'), findsOneWidget);
        expect(find.text('사람을 만나다'), findsWidgets);
        expect(find.text('Newest story'), findsWidgets);
        final newest = tester.getTopLeft(find.text('Newest story').last);
        final older = tester.getTopLeft(find.text('Older story').last);
        expect(
          newest.dy < older.dy ||
              (newest.dy == older.dy && newest.dx < older.dx),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'home, books and library have distinct content and save selection',
    (tester) async {
      await pumpLibrary(tester, rootPage: const MainTabsPage());
      await tester.pumpAndSettle();
      expect(find.byType(MonthlyKoofySection), findsOneWidget);
      await capture(tester, 'tabs-home');
      expect(find.byType(LibraryPage), findsNothing);
      await tester.tap(find.text('도서').last);
      await tester.pumpAndSettle();
      expect(find.byType(MonthlyKoofySection), findsNothing);
      expect(find.byType(SegmentedButton<int>), findsNothing);
      await tester.tap(find.text('서재').last);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(MonthlyKoofySection), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getInt(
          MainTabsPage.selectionKey,
        ),
        2,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, 'tabs-library');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('restores library selection on next launch', (tester) async {
    SharedPreferences.setMockInitialValues({MainTabsPage.selectionKey: 2});
    await pumpLibrary(tester, rootPage: const MainTabsPage());
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(find.byType(LibraryPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('settings is a persistent fourth page without a close button', (
    tester,
  ) async {
    await pumpLibrary(tester, rootPage: const MainTabsPage());
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byTooltip('설정')),
      findsNothing,
    );
    await tester.tap(find.text('설정').last);
    await tester.pumpAndSettle();
    expect(find.text('독서 배경'), findsOneWidget);
    expect(find.byTooltip('닫기'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(
      (await SharedPreferences.getInstance()).getInt(MainTabsPage.selectionKey),
      3,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpLibrary(tester, rootPage: const MainTabsPage());
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(find.text('독서 배경'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('wide settings selects individual items in the detail pane', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({MainTabsPage.selectionKey: 3});
    await AppLanguage.instance.select('ko');
    await pumpLibrary(
      tester,
      rootPage: const MainTabsPage(),
      size: const Size(1000, 800),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-sidebar')), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-category-1')));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsNothing);
    expect(find.text('종이색'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-category-0')));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-category-10')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-search-font')), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-search-book')), findsNothing);
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final language in ['ko', 'en', 'ja']) {
    testWidgets('settings avoids notch and hinge with large text: $language', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({MainTabsPage.selectionKey: 3});
      await AppLanguage.instance.initialize();
      await AppLanguage.instance.select(language);
      addTearDown(() => AppLanguage.instance.select('ko'));
      tester.view.padding = const FakeViewPadding(left: 44);
      addTearDown(tester.view.resetPadding);
      await pumpLibrary(
        tester,
        rootPage: const MainTabsPage(),
        size: const Size(1000, 800),
        scale: 1.5,
        features: const [
          ui.DisplayFeature(
            bounds: Rect.fromLTWH(490, 0, 20, 800),
            type: ui.DisplayFeatureType.hinge,
            state: ui.DisplayFeatureState.postureFlat,
          ),
        ],
      );
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(ListView),
      );
      final bounds = tester.getRect(list);
      expect(bounds.left, greaterThanOrEqualTo(44));
      expect(bounds.right, lessThanOrEqualTo(490));
      expect(find.text(tr('독서 배경')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final size in [const Size(320, 700), const Size(1000, 800)]) {
    testWidgets('tabs avoid banner and fit at $size', (tester) async {
      await pumpLibrary(
        tester,
        size: size,
        scale: 1.3,
        rootPage: const MainTabsPage(),
        overlayBanner: const SizedBox(
          key: ValueKey('banner'),
          width: 320,
          height: 50,
        ),
      );
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(NavigationBar));
      final banner = tester.getRect(find.byKey(const ValueKey('banner')));
      expect(menu.overlaps(banner), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final language in ['en', 'ja']) {
    testWidgets('localized navigation fits a narrow screen: $language', (
      tester,
    ) async {
      await AppLanguage.instance.initialize();
      await AppLanguage.instance.select(language);
      addTearDown(() => AppLanguage.instance.select('ko'));
      await pumpLibrary(
        tester,
        size: const Size(320, 700),
        rootPage: const MainTabsPage(),
      );
      await tester.pumpAndSettle();
      expect(find.text(tr('도서')), findsOneWidget);
      expect(find.text(tr('서재')), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
