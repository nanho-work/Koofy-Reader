import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/theme/app_appearance.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'app theme persists and leaves explicit reading backgrounds independent',
    () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppAppearance();
      await app.initialize();
      expect(app.mode, ThemeMode.system);
      for (final mode in ThemeMode.values) {
        await app.select(mode);
        final reopened = AppAppearance();
        await reopened.initialize();
        expect(reopened.mode, mode);
        for (final background in ['app', 'sepia', 'light', 'dark']) {
          final prefs = defaultReaderPreferences()..theme = background;
          expect(
            preferencesFromJson(preferencesToJson(prefs)).theme,
            background,
          );
        }
        reopened.dispose();
      }
      await app.selectBackground('sepia');
      final paper = AppAppearance();
      await paper.initialize();
      expect(paper.selection, 'sepia');
      expect(paper.mode, ThemeMode.light);
      paper.dispose();
      expect(defaultReaderPreferences().theme, 'app');
      expect(
        preferencesFromJson(
          '{"fontScale":1,"columnCount":0,"scroll":false,"theme":"sepia"}',
        ).theme,
        'sepia',
      );
      app.dispose();
    },
  );
}
