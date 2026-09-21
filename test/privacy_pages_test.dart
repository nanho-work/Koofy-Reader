import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/privacy/data/privacy_service.dart';
import 'package:koofy_reader/features/privacy/presentation/privacy_pages.dart';
import 'privacy_service_test.dart'
    show MemoryPrivacyStorage, FakePrivacyPlatform;

void main() {
  testWidgets(
    'first launch requires a choice; declining opens reading without ATT',
    (tester) async {
      final platform = FakePrivacyPlatform();
      final service = PrivacyService(
        storage: MemoryPrivacyStorage(),
        platform: platform,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(
            home: PrivacyGate(child: Scaffold(body: Text('독서 가능'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('독서 가능'), findsNothing);
      expect(platform.configured, isEmpty);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('비맞춤형 광고 이용'));
      await tester.tap(find.text('비맞춤형 광고 이용'));
      await tester.pump();
      await tester.ensureVisible(find.text('선택하고 시작하기'));
      await tester.tap(find.text('선택하고 시작하기'));
      await tester.pumpAndSettle();
      expect(find.text('독서 가능'), findsOneWidget);
      expect(platform.requests, 0);
      expect(service.state.canRequestAds, true);
      expect(platform.configured.last, false);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );

  testWidgets(
    'consent and offline policy remain reachable at 320px with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = PrivacyService(
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
            home: const PrivacyGate(child: SizedBox.shrink()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('개인정보처리방침 읽기'), 240);
      await tester.tap(find.text('개인정보처리방침 읽기'));
      await tester.pumpAndSettle();
      expect(find.text('쿠피리더 개인정보처리방침'), findsOneWidget);
      expect(
        find.text('최종 업데이트: ${PrivacyService.policyVersion}'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('맞춤형 광고 허용 (선택)'), 240);
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
        storage: MemoryPrivacyStorage(),
        platform: FakePrivacyPlatform(),
      );
      await service.choose(AdvertisingChoice.standard);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [privacyServiceProvider.overrideWithValue(service)],
          child: const MaterialApp(home: PrivacySettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('비맞춤형 광고'), findsOneWidget);
      await tester.ensureVisible(find.text('부적절한 광고 신고'));
      await tester.tap(find.text('부적절한 광고 신고'));
      await tester.pumpAndSettle();
      expect(find.text(readerSupportEmail), findsOneWidget);
      expect(find.text('메일 작성하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      service.dispose();
    },
  );
}
