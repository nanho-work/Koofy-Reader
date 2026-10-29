import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/privacy/data/privacy_service.dart';
import 'package:koofy_reader/features/privacy/presentation/privacy_pages.dart';
import 'privacy_service_test.dart'
    show MemoryPrivacyStorage, FakePrivacyPlatform, FakeAdConsent;

void main() {
  late ReaderAnalytics analytics;
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    SharedPreferences.setMockInitialValues({});
    analytics = ReaderAnalytics(storage: MemoryPrivacyStorage());
    await analytics.initialize();
  });
  testWidgets('Android first launch keeps explicit ad choices without ATT', (
    tester,
  ) async {
    final platform = FakePrivacyPlatform(isIOS: false);
    final service = PrivacyService(
      consent: FakeAdConsent(),
      storage: MemoryPrivacyStorage(),
      platform: platform,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [privacyServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: PrivacyGate(
            analytics: analytics,
            child: Scaffold(body: Text('독서 가능')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('독서 가능'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(platform.configured, isEmpty);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('계속'));
    await tester.tap(find.text('계속'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.text('독서 가능'), findsOneWidget);
    expect(platform.requests, 0);
    expect(service.state.canRequestAds, true);
    expect(platform.configured.last, false);
    expect(analytics.choice, false);
    await tester.pumpWidget(const SizedBox.shrink());
    service.dispose();
  });

  testWidgets(
    'consent and offline policy remain reachable at 320px with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PrivacyService(
        consent: FakeAdConsent(),
        storage: MemoryPrivacyStorage(),
        platform: FakePrivacyPlatform(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.7)),
              child: child!,
            ),
            home: PrivacyGate(analytics: analytics, child: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('개인정보처리방침 읽기'), 240);
      await tester.tap(find.text('개인정보처리방침 읽기'));
      await tester.pumpAndSettle();
      expect(find.text('쿠피리더 개인정보처리방침'), findsOneWidget);
      expect(
        find.text('최종 업데이트: ${PrivacyService.documentUpdatedAt}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('계속'), 240);
      expect(tester.takeException(), isNull);
      expect(service.state.choice, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  testWidgets(
    'settings exposes policy and user initiated ad report with contact',
    (tester) async {
      final service = PrivacyService(
        consent: FakeAdConsent(),
        storage: MemoryPrivacyStorage(),
        platform: FakePrivacyPlatform(),
      );
      await service.choose(AdvertisingChoice.standard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: MaterialApp(home: PrivacySettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('비맞춤형 광고'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('부적절한 광고 신고'), 200);
      await tester.tap(find.text('부적절한 광고 신고'));
      await tester.pumpAndSettle();
      expect(find.text(readerSupportEmail), findsOneWidget);
      expect(find.text('메일 작성하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  for (final result in ['authorized', 'denied', 'restricted']) {
    testWidgets('iOS Continue routes to ATT and allows reading after $result', (
      tester,
    ) async {
      final platform = FakePrivacyPlatform()..requestResult = result;
      final service = PrivacyService(
        consent: FakeAdConsent(),
        storage: MemoryPrivacyStorage(),
        platform: platform,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            home: PrivacyGate(
              analytics: analytics,
              child: Scaffold(body: Text('독서 가능')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('비맞춤형 광고 이용'), findsNothing);
      expect(find.text('맞춤형 광고 허용 (선택)'), findsNothing);
      expect(find.byType(RadioGroup<AdvertisingChoice>), findsNothing);
      expect(platform.requests, 0);
      expect(platform.configured, isEmpty);
      await tester.ensureVisible(find.text('계속'));
      await tester.tap(find.text('계속'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(platform.requests, 1);
      expect(find.text('독서 가능'), findsOneWidget);
      expect(platform.configured.last, result == 'authorized');
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    });
  }

  testWidgets(
    'iOS settings preserve refusal and do not request ATT on toggle',
    (tester) async {
      final platform = FakePrivacyPlatform();
      final service = PrivacyService(
        consent: FakeAdConsent(),
        storage: MemoryPrivacyStorage(),
        platform: platform,
      );
      await service.choose(AdvertisingChoice.standard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            home: PrivacyGate(
              analytics: analytics,
              child: PrivacySettingsPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('계속'), findsNothing);
      expect(find.text('광고 선택'), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '비맞춤형 광고만 사용'),
            )
            .value,
        true,
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '비맞춤형 광고만 사용'));
      await tester.pumpAndSettle();
      expect(service.state.choice, AdvertisingChoice.systemTracking);
      expect(find.text('비맞춤형 광고'), findsOneWidget);
      expect(service.state.effectivePersonalized, false);
      expect(platform.requests, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );
  testWidgets(
    'returning reader retains choices and does not see welcome again',
    (tester) async {
      await tester.runAsync(() => analytics.choose(false));
      final service = PrivacyService(
        storage: MemoryPrivacyStorage(),
        platform: FakePrivacyPlatform(),
        consent: FakeAdConsent(),
      );
      await service.choose(AdvertisingChoice.standard);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            builder: (context, child) => PrivacyGate(
              navigatorKey: navigatorKey,
              analytics: analytics,
              child: child!,
            ),
            home: const Scaffold(body: Text('main ready')),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('main ready'), findsOneWidget);
      expect(find.byType(PrivacyWelcomeDialog), findsNothing);
      expect(analytics.choice, false);
      expect(service.state.choice, AdvertisingChoice.standard);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );
}
