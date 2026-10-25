import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/monthly_koofy_section.dart';
import 'helpers/catalog_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'monthly groups retain locators and do not take books from user groups',
    () async {
      final repository = BookGroupRepository(SharedPrefsLocalStorage());
      await repository.addMonthlyEpisode('issue', '10월호', 'episode2', [
        'episode1',
        'episode2',
      ]);
      await repository.addMonthlyEpisode('issue', '10월호', 'episode1', [
        'episode1',
        'episode2',
      ]);
      await repository.addMonthlyEpisode('issue', '10월호', 'episode1', [
        'episode1',
        'episode2',
      ]);
      final group = (await repository.load()).single;
      expect(group.bookIds, ['episode1', 'episode2']);
      expect(group.showMemberCovers, true);
      await repository.create('내가 만든 묶음', ['other1', 'other2']);
      await repository.addMonthlyEpisode('issue', '10월호', 'other1', ['other1']);
      expect((await repository.load()).first.bookIds, ['episode1', 'episode2']);
    },
  );
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
      expect(find.text('오늘의 쿠피'), findsOneWidget);
      expect(find.text('첫 이야기'), findsOneWidget);
      expect(find.text('지난 이야기'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
