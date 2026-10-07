import 'package:koofy_reader/features/privacy/data/privacy_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/domain/ad_state.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:koofy_reader/features/ads/presentation/app_ad_route_observer.dart';
import 'package:koofy_reader/features/ads/presentation/app_footer_ad_shell.dart';
import 'package:koofy_reader/features/ads/presentation/banner_ad_widget.dart';

void main() {
  testWidgets('reward removes overlay clearance without resizing the page', (
    tester,
  ) async {
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
    var inset = 0.0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
            child: AppFooterAdShell(
              child: Builder(
                builder: (context) {
                  inset = AdOverlayInsets.bottomOf(context);
                  return Container(key: bodyKey);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byKey(bodyKey));
    expect(inset, 100);
    expect(find.text('오프라인에서도 독서를 계속할 수 있습니다.'), findsNothing);
    hidden = true;
    container.invalidate(adStateProvider);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(bodyKey)), before);
    expect(inset, 0);
    expect(find.byType(AdFooterWidget), findsNothing);
    hidden = false;
    container.invalidate(adStateProvider);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(bodyKey)), before);
    expect(inset, 100);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets(
    'only the creative intercepts taps; side margins reach the full screen page',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var bodyTaps = 0, adTaps = 0;
      const bodyKey = ValueKey('body'), bannerKey = ValueKey('banner');
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
            child: AppBannerOverlay(
              banner: GestureDetector(
                key: bannerKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => adTaps++,
                child: const ColoredBox(color: Colors.blue),
              ),
              child: GestureDetector(
                key: bodyKey,
                behavior: HitTestBehavior.opaque,
                onTap: () => bodyTaps++,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(bodyKey)), const Size(390, 844));
      expect(
        tester.getRect(find.byKey(bannerKey)),
        const Rect.fromLTWH(35, 760, 320, 50),
      );
      await tester.tapAt(const Offset(15, 780));
      await tester.tapAt(const Offset(375, 780));
      expect(bodyTaps, 2);
      await tester.tapAt(const Offset(190, 780));
      expect(adTaps, 1);
      expect(bodyTaps, 2);
    },
  );

  testWidgets(
    'scrolling beside the banner works and the final item clears it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const bannerKey = ValueKey('banner');
      await tester.pumpWidget(
        MaterialApp(
          home: AppBannerOverlay(
            banner: const ColoredBox(key: bannerKey, color: Colors.blue),
            child: Builder(
              builder: (context) => ListView.builder(
                controller: controller,
                itemCount: 30,
                itemExtent: 60,
                padding: AdOverlayInsets.padding(
                  context,
                  const EdgeInsets.all(16),
                ),
                itemBuilder: (_, i) => Text('row $i'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(15, 810), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(
        tester.getBottomLeft(find.text('row 29')).dy,
        lessThan(tester.getTopLeft(find.byKey(bannerKey)).dy),
      );
    },
  );

  testWidgets('keyboard and screens narrower than the creative hide overlay', (
    tester,
  ) async {
    const adKey = ValueKey('ad');
    Future<void> pump(double width, double keyboard) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: const AppBannerOverlay(
              banner: SizedBox(key: adKey),
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
    }

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(390, 250);
    expect(find.byKey(adKey), findsNothing);
    await pump(280, 0);
    expect(find.byKey(adKey), findsNothing);
    await pump(390, 0);
    expect(find.byKey(adKey), findsOneWidget);
  });

  testWidgets('unavailable banner is invisible and cannot intercept touches', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppBannerOverlay(
          banner: const BannerAdWidget(showStatusMessages: false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(BannerAdWidget)));
    expect(taps, 1);
    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(BannerAdWidget),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0);
  });

  testWidgets(
    'reader routes and popup sheets suppress app overlay and restore it on return',
    (tester) async {
      final observer = AppAdRouteObserver();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          home: const Scaffold(body: Text('library')),
        ),
      );
      await tester.pumpAndSettle();
      expect(observer.visible.value, true);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: AppRoutes.nativeReader),
          builder: (_) => const Scaffold(body: Text('reader')),
        ),
      );
      await tester.pumpAndSettle();
      expect(observer.visible.value, false);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(observer.visible.value, true);
      showModalBottomSheet<void>(
        context: tester.element(find.text('library')),
        builder: (_) => const SizedBox(height: 200, child: Text('sheet')),
      );
      await tester.pumpAndSettle();
      expect(observer.visible.value, false);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(observer.visible.value, true);
      await tester.pumpWidget(const SizedBox.shrink());
      observer.visible.dispose();
    },
  );
}
