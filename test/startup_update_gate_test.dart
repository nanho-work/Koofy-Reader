import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/updates/data/update_service.dart';
import 'package:koofy_reader/features/updates/domain/update_policy.dart';
import 'package:koofy_reader/features/updates/presentation/startup_update_gate.dart';
import 'update_policy_test.dart' show updateValues;
import 'update_service_test.dart' show FakeUpdateSource;

Widget app(
  UpdateService service, {
  Future<bool> Function(Uri)? open,
  bool large = false,
}) => ProviderScope(
  overrides: [
    updateServiceProvider.overrideWithValue(service),
    updateLinkLauncherProvider.overrideWithValue(open ?? (_) async => true),
  ],
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
      child: child!,
    ),
    home: const StartupUpdateGate(child: Scaffold(body: Text('서재'))),
  ),
);
UpdateService service(FakeUpdateSource source) => UpdateService(
  source: source,
  platform: UpdatePlatform.android,
  installedVersion: () async => '1.0.0',
);
void main() {
  testWidgets(
    'optional notice can be deferred; resume and rebuild never repeat it',
    (tester) async {
      final source = FakeUpdateSource(updateValues());
      final updates = service(source);
      await tester.pumpWidget(app(updates));
      await tester.pumpAndSettle();
      expect(find.text('서재'), findsNothing);
      await tester.tap(find.text('나중에'));
      await tester.pumpAndSettle();
      expect(find.text('서재'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(app(updates));
      await tester.pumpAndSettle();
      expect(find.text('서재'), findsOneWidget);
      expect(source.calls, 1);
    },
  );
  testWidgets(
    'below minimum has no defer; correct store URL opens; failure remains retryable',
    (tester) async {
      final source = FakeUpdateSource(updateValues(minimum: '1.2.0'));
      final updates = service(source);
      final links = <Uri>[];
      await tester.pumpWidget(
        app(
          updates,
          open: (uri) async {
            links.add(uri);
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('나중에'), findsNothing);
      expect(find.text('서재'), findsNothing);
      await tester.tap(find.text('업데이트'));
      await tester.pumpAndSettle();
      expect(
        links.single.toString(),
        source.values['android_update_store_url'],
      );
      expect(find.textContaining('스토어를 열지 못했습니다'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'successful store launch does not recheck or auto-dismiss mandatory notice',
    (tester) async {
      final source = FakeUpdateSource(updateValues(minimum: '1.2.0'));
      final updates = service(source);
      await tester.pumpWidget(app(updates));
      await tester.pumpAndSettle();
      await tester.tap(find.text('업데이트'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('업데이트가 필요합니다'), findsOneWidget);
      expect(source.calls, 1);
    },
  );
  testWidgets('320px and large text keep both choices reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(service(FakeUpdateSource(updateValues())), large: true),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('나중에'));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(find.text('서재'), findsOneWidget);
  });
  testWidgets(
    'a late mandatory response cannot interrupt reading after timeout',
    (tester) async {
      final source = FakeUpdateSource(updateValues())..pending = Completer();
      final updates = UpdateService(
        source: source,
        platform: UpdatePlatform.android,
        installedVersion: () async => '1.0.0',
        timeout: const Duration(milliseconds: 100),
      );
      await tester.pumpWidget(app(updates));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.text('서재'), findsOneWidget);
      source.pending!.complete(updateValues(minimum: '1.2.0'));
      await tester.pumpAndSettle();
      expect(find.text('서재'), findsOneWidget);
      expect(find.text('업데이트가 필요합니다'), findsNothing);
    },
  );
}
