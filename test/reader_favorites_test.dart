import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/notifications/reader_notifications.dart';
import 'package:koofy_reader/features/notifications/notification_widgets.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_page.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'helpers/catalog_fixture.dart';

class FakeNotificationPlatform implements ReaderNotificationPlatform {
  @override
  bool available = true;
  ReaderNotificationPermission status = ReaderNotificationPermission.denied;
  int requests = 0, settingsOpened = 0;
  bool fails = false;
  final topics = <String>{};
  @override
  Future<ReaderNotificationPermission> permission({
    bool request = false,
  }) async {
    if (request) requests++;
    return status;
  }

  @override
  Future<void> autoInit(bool enabled) async {}
  @override
  Future<bool> apnsReady() async => true;
  @override
  Future<void> openSettings() async {
    settingsOpened++;
  }

  @override
  Future<void> subscribe(String topic) async {
    if (fails) throw StateError('offline');
    topics.add(topic);
  }

  @override
  Future<void> unsubscribe(String topic) async {
    if (fails) throw StateError('offline');
    topics.remove(topic);
  }
}

const work = 'work_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'waits for asynchronous APNs registration before subscriptions',
    () async {
      var checks = 0, pauses = 0;
      expect(
        await waitForReaderApns(
          () async => ++checks == 3,
          pause: (_) async {
            pauses++;
          },
        ),
        true,
      );
      expect(checks, 3);
      expect(pauses, 2);
    },
  );
  test('APNs wait is bounded and does not hide SDK failures', () async {
    var pauses = 0;
    expect(
      await waitForReaderApns(
        () async => false,
        attempts: 3,
        pause: (_) async {
          pauses++;
        },
      ),
      false,
    );
    expect(pauses, 2);
    await expectLater(
      waitForReaderApns(() async => throw StateError('offline')),
      throwsStateError,
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.initialize();
    await AppLanguage.instance.select('ko');
  });
  test(
    'favorites persist without Firebase or permission and never request permission',
    () async {
      final platform = FakeNotificationPlatform()..available = false;
      final service = ReaderNotifications(platform: platform);
      await service.setFavorite(work, 'A book', true);
      final restored = ReaderNotifications(platform: platform);
      await restored.initialize();
      expect(restored.favorites[work], 'A book');
      expect(platform.requests, 0);
      expect(platform.topics, isEmpty);
      await restored.setFavorite(work, 'A book', false);
      expect(restored.favorites, isEmpty);
    },
  );
  test(
    'first reading prompts once across concurrent events and restart',
    () async {
      final platform = FakeNotificationPlatform();
      final service = ReaderNotifications(platform: platform);
      await service.initialize();
      expect(platform.requests, 0);
      await Future.wait([service.firstReading(), service.firstReading()]);
      expect(platform.requests, 1);
      final restored = ReaderNotifications(platform: platform);
      await restored.firstReading();
      expect(platform.requests, 1);
      expect(restored.allowed, false);
      await restored.setFavorite(work, 'Denied but saved', true);
      expect(restored.favorites.length, 1);
      expect(platform.requests, 1);
      expect(await restored.claimFavoriteNotice(), true);
      expect(await restored.claimFavoriteNotice(), false);
      final again = ReaderNotifications(platform: platform);
      await again.initialize();
      expect(await again.claimFavoriteNotice(), false);
    },
  );
  test(
    'old work/monthly opt-ins migrate and old global choice is preserved separately',
    () async {
      SharedPreferences.setMockInitialValues({
        ReaderNotifications.preference: jsonEncode({
          'subscriptions': {
            work: 'Old favorite',
            'monthly': 'October',
            'books': 'All books',
          },
          'actual': ['reader_books_ko'],
        }),
      });
      final platform = FakeNotificationPlatform()
        ..status = ReaderNotificationPermission.allowed;
      final service = ReaderNotifications(platform: platform);
      await service.initialize();
      await service.sync();
      expect(service.favorites.keys.toSet(), {work, 'monthly'});
      expect(service.legacyBooks, true);
      expect(service.asked, true);
      await service.disableLegacyBooks();
      expect(platform.topics, isNot(contains('reader_books_ko')));
      expect(service.favorites.length, 2);
    },
  );
  test(
    'global off keeps favorites; re-enable and language change reconcile topics',
    () async {
      final platform = FakeNotificationPlatform()
        ..status = ReaderNotificationPermission.allowed;
      final service = ReaderNotifications(platform: platform);
      await service.setFavorite(work, 'Book', true);
      await service.setFavorite('monthly', 'October', true);
      expect(platform.topics, {'reader_${work}_ko', 'reader_monthly_ko'});
      await service.disableNotifications();
      expect(platform.topics, isEmpty);
      expect(service.favorites.length, 2);
      await service.enableNotifications();
      await AppLanguage.instance.select('ja');
      await service.sync();
      expect(platform.topics, {'reader_${work}_ja', 'reader_monthly_ja'});
      await service.setFavorite('monthly', 'November', true);
      expect(service.favorites.length, 2);
      await service.setFavorite(work, 'Book', false);
      expect(platform.topics, {'reader_monthly_ja'});
    },
  );
  test(
    'network error retains local favorites and retries synchronization',
    () async {
      final platform = FakeNotificationPlatform()
        ..status = ReaderNotificationPermission.allowed
        ..fails = true;
      final service = ReaderNotifications(platform: platform);
      await service.setFavorite(work, 'Book', true);
      expect(service.favorites[work], 'Book');
      expect(service.connectionError, isNotNull);
      platform.fails = false;
      await service.sync();
      expect(platform.topics, {'reader_${work}_ko'});
      expect(service.connectionError, isNull);
    },
  );
  test(
    'Later on a favorite before reading suppresses automatic reading prompt',
    () async {
      final platform = FakeNotificationPlatform();
      final service = ReaderNotifications(platform: platform);
      await service.setFavorite(work, 'Book', true);
      expect(await service.claimFavoriteNotice(), true);
      await service.firstReading();
      expect(platform.requests, 0);
      final restored = ReaderNotifications(platform: platform);
      await restored.firstReading();
      expect(platform.requests, 0);
      await restored.enableNotifications();
      expect(platform.requests, 1);
    },
  );
  test('rapid mutations preserve all favorites', () async {
    final service = ReaderNotifications(
      platform: FakeNotificationPlatform()..available = false,
    );
    await Future.wait([
      service.setFavorite(work, 'One', true),
      service.setFavorite('monthly', 'Monthly', true),
    ]);
    final restored = ReaderNotifications(
      platform: FakeNotificationPlatform()..available = false,
    );
    await restored.initialize();
    expect(restored.favorites.length, 2);
  });
  test(
    'monthly identity crosses languages and months; completed work identity is unchanged',
    () {
      final a = catalogFixture(1, kind: 'series');
      final b = catalogFixture(2, kind: 'series');
      final october = CatalogItem.fromJson({
        ...a.json,
        'issueMonth': '2026-10',
      });
      final november = CatalogItem.fromJson({
        ...b.json,
        'issueMonth': '2026-11',
        'language': 'ja',
      });
      expect(notificationBase(october), notificationBase(november));
      expect(
        notificationBase(
          CatalogItem.fromJson({...a.json, 'seriesStatus': 'completed'}),
        ),
        notificationBase(a),
      );
    },
  );
  test(
    'late translation linkage migrates favorites without changing permission',
    () async {
      final platform = FakeNotificationPlatform()..available = false;
      final service = ReaderNotifications(platform: platform);
      final original = catalogFixture(1, kind: 'series');
      await service.setFavorite(
        notificationBase(original),
        original.title,
        true,
      );
      final linked = CatalogItem.fromJson({
        ...original.json,
        'translationGroupId': 'c' * 32,
      });
      expect(service.isFavorite(linked), true);
      await service.reconcile([linked]);
      expect(service.favorites.keys.single, 'work_${'c' * 32}');
      expect(platform.requests, 0);
      final translated = CatalogItem.fromJson({
        ...catalogFixture(2, kind: 'series').json,
        'translationGroupId': 'c' * 32,
      });
      expect(service.isFavorite(translated), true);
    },
  );
  test(
    'returning from OS settings keeps global enable intent and reconciles favorites',
    () async {
      final platform = FakeNotificationPlatform();
      final service = ReaderNotifications(platform: platform);
      await service.setFavorite(work, 'Book', true);
      await service.disableNotifications();
      await service.openSettings();
      expect(platform.settingsOpened, 1);
      expect(service.enabled, true);
      platform.status = ReaderNotificationPermission.allowed;
      await service.sync();
      expect(platform.topics, {'reader_${work}_ko'});
    },
  );
  testWidgets(
    'cover star saves without downloading and favorites filter keeps completed works',
    (tester) async {
      final platform = FakeNotificationPlatform()..available = false;
      final service = ReaderNotifications(platform: platform);
      await service.initialize();
      final item = CatalogItem.fromJson({
        ...catalogFixture(1, kind: 'series', title: 'Completed story').json,
        'seriesStatus': 'completed',
      });
      final catalog = FakeReaderCatalog([
        item,
        catalogFixture(2, title: 'Not starred'),
      ]);
      addTearDown(catalog.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerNotificationsProvider.overrideWith((ref) => service),
            readerCatalogProvider.overrideWithValue(catalog),
            booksProvider.overrideWith((ref) async => []),
          ],
          child: const MaterialApp(home: ReaderCatalogPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('favorite-${item.id}')));
      await tester.pumpAndSettle();
      expect(service.isFavorite(item), true);
      expect(catalog.installed, isEmpty);
      await tester.tap(find.widgetWithText(ChoiceChip, '즐겨찾기'));
      await tester.pumpAndSettle();
      expect(find.text('Completed story'), findsOneWidget);
      expect(find.text('Not starred'), findsNothing);
      await tester.tap(find.byKey(ValueKey('favorite-${item.id}')));
      await tester.pumpAndSettle();
      expect(find.text('즐겨찾기한 책이 없습니다. 책의 별표를 눌러 추가해 보세요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'favorite notice is app-owned, denial keeps favorite, settings have no per-work switches',
    (tester) async {
      final platform = FakeNotificationPlatform();
      final service = ReaderNotifications(platform: platform);
      final item = catalogFixture(1);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerNotificationsProvider.overrideWith((ref) => service),
          ],
          child: MaterialApp(
            home: Scaffold(body: FavoriteButton(item: item)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('favorite-${item.id}')));
      await tester.pumpAndSettle();
      expect(find.text('새 이야기 알림'), findsOneWidget);
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
      expect(service.isFavorite(item), true);
      expect(platform.requests, 0);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            readerNotificationsProvider.overrideWith((ref) => service),
          ],
          child: const MaterialApp(home: NotificationSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(item.title), findsNothing);
      expect(find.text('즐겨찾기 새 글 알림'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
