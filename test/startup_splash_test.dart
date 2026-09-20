import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/app/branding/startup_splash.dart';

void main() {
  Widget app({bool reducedMotion = false}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: const StartupSplash(child: Text('library')),
    ),
  );

  testWidgets('cold start completes once; rebuild and resume do not replay', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(find.byKey(const ValueKey('startup-splash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('startup-splash')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.byKey(const ValueKey('startup-splash')), findsNothing);
    await tester.pumpWidget(app());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byKey(const ValueKey('startup-splash')), findsNothing);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('reduced motion opens library immediately', (tester) async {
    await tester.pumpWidget(app(reducedMotion: true));
    expect(find.byKey(const ValueKey('startup-splash')), findsNothing);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('turning on reduced motion stops the active animation', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(app(reducedMotion: true));
    expect(find.byKey(const ValueKey('startup-splash')), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
