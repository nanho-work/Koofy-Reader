// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/app/app.dart';

void main() {
  testWidgets('Library screen renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: KoofyReaderApp()));
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('쿠피 리더').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.text('쿠피 리더'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
