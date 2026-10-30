import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/ads/presentation/reward_ad_button.dart';

void main() {
  testWidgets(
    'countdown disables viewing, catches up after resume and enables on expiry',
    (tester) async {
      var now = DateTime(2026, 10, 30);
      final expiry = now.add(const Duration(hours: 4));
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RewardAdButton(
              hiddenUntil: expiry,
              busy: false,
              now: () => now,
              onPressed: () => calls++,
            ),
          ),
        ),
      );
      expect(find.text('04:00:00'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('03:59:59'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = expiry.subtract(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('00:00:01'), findsOneWidget);
      now = expiry;
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('ad-reward-countdown')), findsNothing);
      await tester.tap(find.byType(FilledButton));
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
