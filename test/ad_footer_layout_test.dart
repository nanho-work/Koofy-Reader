import 'package:koofy_reader/features/privacy/data/privacy_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/domain/ad_state.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/ads/presentation/app_footer_ad_shell.dart';

void main() {
  testWidgets(
    'reward removes footer and its safe-area space; expiry restores it',
    (tester) async {
      var hidden = false;
      final container = ProviderContainer(
        overrides: [
          privacyStateProvider.overrideWith(
            (ref) => Stream.value(
              const PrivacyState(
                loaded: true,
                choice: AdvertisingChoice.standard,
                configured: true,
              ),
            ),
          ),
          adStateProvider.overrideWith(
            (ref) async => AdState(
              hiddenUntil: hidden
                  ? DateTime.now().add(const Duration(hours: 2))
                  : null,
            ),
          ),
          connectivityResultsProvider.overrideWith(
            (ref) => Stream.value([ConnectivityResult.none]),
          ),
        ],
      );
      const bodyKey = ValueKey('body');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
              child: AppFooterAdShell(child: Container(key: bodyKey)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester.getSize(find.byKey(bodyKey)).height;
      expect(find.text('네트워크 연결 필요'), findsOneWidget);
      hidden = true;
      container.invalidate(adStateProvider);
      await tester.pumpAndSettle();
      final expanded = tester.getSize(find.byKey(bodyKey)).height;
      expect(expanded, greaterThan(before + 34));
      expect(find.byType(AdFooterWidget), findsNothing);
      expect(find.text('광고 숨김 적용 중'), findsNothing);
      hidden = false;
      container.invalidate(adStateProvider);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(bodyKey)).height, before);
      expect(find.text('네트워크 연결 필요'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
}
