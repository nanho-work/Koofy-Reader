import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/notifications/reader_notifications.dart';
import 'package:koofy_reader/features/notifications/upcoming_episode_notice.dart';
import 'helpers/catalog_fixture.dart';
import 'reader_favorites_test.dart' show FakeNotificationPlatform;

void main() {
  for (final monthly in [false, true]) {
    testWidgets(
      'upcoming ${monthly ? 'monthly' : 'serial'} favorites the whole work, never an episode',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final platform = FakeNotificationPlatform()..available = false;
        final service = ReaderNotifications(platform: platform);
        addTearDown(service.dispose);
        final raw = catalogFixture(40, kind: 'series', title: '작품 이름');
        final work = CatalogItem.fromJson({
          ...raw.json,
          if (monthly) 'issueMonth': '2026-11',
          if (!monthly) 'translationGroupId': 'b' * 32,
        });
        final episodeRaw = catalogFixture(
          41,
          seriesId: work.id,
          episodeNumber: 2,
        );
        final episode = CatalogItem.fromJson({
          ...episodeRaw.json,
          'upcoming': true,
          if (monthly) 'issueMonth': '2026-11',
        });
        final catalog = FakeReaderCatalog([work, episode]);
        addTearDown(catalog.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              readerCatalogProvider.overrideWithValue(catalog),
              readerNotificationsProvider.overrideWithValue(service),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showUpcomingEpisodeNotice(
                    context,
                    episode,
                    message: '공개 날짜 안내',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('공개 날짜 안내'), findsOneWidget);
        await tester.tap(find.text('작품 즐겨찾기'));
        await tester.pumpAndSettle();
        expect(
          service.containsBase(monthly ? 'monthly' : 'work_${'b' * 32}'),
          isTrue,
        );
        expect(service.containsBase('work_${episode.id}'), isFalse);
        expect(service.favorites.values.single, work.title);
        expect(find.text('즐겨찾기한 작품입니다'), findsOneWidget);
        expect(platform.requests, 0);
        await tester.tap(find.text('닫기'));
        await tester.pumpAndSettle();
        expect(service.isFavorite(work), isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'existing favorite offers explicit settings action without requesting OS permission again',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final platform = FakeNotificationPlatform();
      final service = ReaderNotifications(platform: platform);
      addTearDown(service.dispose);
      await service.initialize();
      service.asked = true;
      final work = catalogFixture(50, kind: 'series');
      final episode = catalogFixture(51, seriesId: work.id, episodeNumber: 2);
      await service.setFavorite(notificationBase(work), work.title, true);
      final catalog = FakeReaderCatalog([work, episode]);
      addTearDown(catalog.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerCatalogProvider.overrideWithValue(catalog),
            readerNotificationsProvider.overrideWithValue(service),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showUpcomingEpisodeNotice(context, episode, message: '예정'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('즐겨찾기한 작품입니다'), findsOneWidget);
      await tester.tap(find.text('새 글 알림 받기'));
      await tester.pumpAndSettle();
      expect(platform.settingsOpened, 1);
      expect(platform.requests, 0);
      expect(service.isFavorite(work), true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
