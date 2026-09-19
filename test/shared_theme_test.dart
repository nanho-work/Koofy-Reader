import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/domain/ad_state.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/ads/presentation/app_footer_ad_shell.dart';
import 'package:koofy_reader/features/settings/presentation/settings_page.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('settings and offline ad share the $brightness canvas', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adStateProvider.overrideWith(
              (ref) async => const AdState(hiddenUntil: null),
            ),
            connectivityResultsProvider.overrideWith(
              (ref) => Stream.value([ConnectivityResult.none]),
            ),
          ],
          child: MaterialApp(
            theme: KoofyTheme.forBrightness(brightness),
            builder: (context, child) => AppFooterAdShell(child: child!),
            home: const SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(SettingsPage));
      final theme = Theme.of(context);
      final canvas = theme.scaffoldBackgroundColor;
      expect(theme.appBarTheme.backgroundColor, canvas);
      final footer = tester.widgetList<Container>(
        find.ancestor(
          of: find.text('네트워크 연결 필요'),
          matching: find.byType(Container),
        ),
      );
      expect(footer.first.color, canvas);
      final shell = tester.widgetList<ColoredBox>(
        find.descendant(
          of: find.byType(AppFooterAdShell),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(shell.first.color, canvas);
      expect(tester.takeException(), isNull);
    });
  }
}
