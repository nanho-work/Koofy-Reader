import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/reading_diary/data/reading_diary.dart';
import 'package:koofy_reader/features/reading_diary/presentation/reading_diary_page.dart';
import 'library_page_test.dart' show pumpLibrary, capture;

void main() {
  for (final language in ['ko', 'en', 'ja']) {
    for (final size in [
      const Size(320, 700),
      const Size(840, 700),
      const Size(1200, 900),
    ]) {
      testWidgets('calendar, day shelf and graphs fit $language/$size', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        await AppLanguage.instance.initialize();
        await AppLanguage.instance.select(language);
        addTearDown(() => AppLanguage.instance.select('ko'));
        final diary = ReadingDiary(SharedPrefsLocalStorage());
        for (final day in [1, 2, 4, 7, 10, 15, 18, 22, 25, 29]) {
          await diary.add(
            const DiaryBook(id: 'book', title: 'The Little Mermaid'),
            DateTime(2026, 11, day, 12),
            Duration(minutes: day * 3),
          );
        }
        await diary.add(
          const DiaryBook(id: 'other', title: 'A small story'),
          DateTime(2026, 11, 2, 15),
          const Duration(minutes: 41),
        );
        await pumpLibrary(
          tester,
          size: size,
          scale: 1.3,
          rootPage: ReadingDiaryPage(now: DateTime(2026, 11, 30)),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip(tr('이전')), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == tr('이전'),
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/diary/koofy_stamp.png'),
            tester.element(find.byType(ReadingDiaryPage)),
          ),
        );
        await tester.pumpAndSettle();
        await capture(tester, 'diary-$language-${size.width.toInt()}');
        expect(
          tester.getRect(find.byKey(const ValueKey('diary-day-29'))).bottom,
          lessThanOrEqualTo(size.height + 1),
        );
        await tester.tap(find.byKey(const ValueKey('diary-day-2')));
        await tester.pumpAndSettle();
        expect(find.text('The Little Mermaid'), findsWidgets);
        expect(find.text('A small story'), findsWidgets);
        await capture(tester, 'diary-detail-$language-${size.width.toInt()}');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(tr('그래프 보기')));
        await tester.pumpAndSettle();
        expect(find.text(tr('일별')), findsOneWidget);
        expect(find.text(tr('월별')), findsOneWidget);
        await tester.tap(find.byTooltip(tr('확대')));
        await tester.pump();
        await tester.tap(find.byTooltip(tr('전체 보기')));
        await tester.pump();
        await capture(tester, 'diary-graph-$language-${size.width.toInt()}');
        final chart = tester.getRect(
          find.byKey(const ValueKey('reading-line-chart')),
        );
        await tester.tapAt(
          Offset(chart.left + 48 + (chart.width - 64) / 29, chart.center.dy),
        );
        await tester.pumpAndSettle();
        await capture(tester, 'diary-selected-$language-${size.width.toInt()}');
        await tester.tap(find.text(tr('월별')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final size in [const Size(900, 420), const Size(320, 700)]) {
    testWidgets('large text and short windows remain usable at $size', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.instance.initialize();
      await AppLanguage.instance.select('en');
      addTearDown(() => AppLanguage.instance.select('ko'));
      await pumpLibrary(
        tester,
        size: size,
        scale: 1.8,
        rootPage: ReadingDiaryPage(now: DateTime(2026, 11, 2)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tr('그래프 보기')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('empty diary disables dates and caps navigation at next month', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.select('ko');
    await pumpLibrary(
      tester,
      rootPage: ReadingDiaryPage(now: DateTime(2026, 11, 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('책을 읽으면 쿠피가 여기에 남아요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diary-day-2')));
    await tester.pumpAndSettle();
    expect(find.byType(DiaryDayPage), findsNothing);
    await tester.tap(find.byTooltip(tr('다음')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == tr('다음'),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
