import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:koofy_reader/features/analytics/presentation/analytics_choice.dart';

void main() {
  for (final allow in [true, false]) {
    testWidgets(
      'analytics choice $allow allows reading and is separate from ads',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final analytics = ReaderAnalytics(writer: (_, _) async {});
        await analytics.initialize();
        await tester.pumpWidget(
          MaterialApp(
            home: AnalyticsChoice(
              service: analytics,
              child: const Text('library'),
            ),
          ),
        );
        expect(find.text('library'), findsNothing);
        final button = find.text(allow ? '사용 통계 허용' : '허용하지 않고 계속');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(analytics.choice, allow);
        expect(find.text('library'), findsOneWidget);
      },
    );
  }
}
