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
  for (final ios in [false, true]) {
    testWidgets('startup only runs required consent on iOS=$ios', (
      tester,
    ) async {
      final platform = FakePrivacyPlatform(isIOS: ios);
      final consent = FakeAdConsent();
      final service = PrivacyService(
        consent: consent,
        storage: MemoryPrivacyStorage(),
        platform: platform,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: MaterialApp(
            home: PrivacyGate(
              analytics: analytics,
              child: const Scaffold(body: Text('독서 가능')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('독서 가능'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(platform.requests, 0);
      expect(consent.prepares, 1);
      expect(service.state.canRequestAds, true);
      expect(platform.configured.last, false);
      expect(analytics.choice, isNot(true));
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    });
  }

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
      expect(find.byType(AlertDialog), findsNothing);
      expect(analytics.choice, false);
      expect(service.state.choice, AdvertisingChoice.standard);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );
}
