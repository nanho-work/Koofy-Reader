import 'package:koofy_reader/features/updates/data/update_service.dart';
import 'package:koofy_reader/features/privacy/data/privacy_service.dart';
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
import 'package:koofy_reader/features/home/presentation/main_tabs_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App opens the home tabs without a legacy header', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateServiceProvider.overrideWithValue(
            UpdateService(
              source: FirebaseUpdateSource(),
              platform: null,
              installedVersion: () async => '1.0.0',
            ),
          ),
          privacyStateProvider.overrideWith(
            (ref) => Stream.value(
              const PrivacyState(
                loaded: true,
                choice: AdvertisingChoice.standard,
                configured: true,
              ),
            ),
          ),
        ],
        child: const KoofyReaderApp(),
      ),
    );
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(MainTabsPage).evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.byType(MainTabsPage), findsOneWidget);
    expect(find.text('내 서재'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });
}
