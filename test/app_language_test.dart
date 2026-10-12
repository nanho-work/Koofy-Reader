import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/book_catalog_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/core/localization/language_button.dart';
import 'package:koofy_reader/core/localization/messages.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('known errors translate without altering unknown diagnostics', () async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.select('en');
    addTearDown(() => AppLanguage.instance.select('ko'));
    expect(
      localizedError(const FormatException('백업 파일이 100MB를 초과합니다.')),
      'The backup file exceeds 100MB.',
    );
    expect(
      localizedError(StateError('책을 닫은 뒤 백업을 이용해 주세요.')),
      'Close the book before using backup.',
    );
    expect(
      localizedError(const FormatException('file abc.txt: disk full')),
      'file abc.txt: disk full',
    );
    await AppLanguage.instance.select('ja');
    expect(
      localizedError(const FormatException('백업 파일이 100MB를 초과합니다.')),
      'バックアップファイルが100MBを超えています。',
    );
  });

  testWidgets('episode label changes language while the title stays original', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => AppLanguage.instance.select('ko'));
    final item = CatalogItem.fromJson({
      'id': 'a' * 32,
      'kind': 'book',
      'title': '인어공주는 파도를 벤다',
      'author': '쿠피',
      'description': '',
      'license': '',
      'version': 1,
      'seriesId': 'b' * 32,
      'episodeNumber': 7,
      'episodeTitle': '파도의 노래',
      'assets': {
        'txt': {'sha256': 'c' * 64, 'size': 10, 'extension': 'txt'},
        'cover': {'sha256': 'd' * 64, 'size': 10, 'extension': 'webp'},
      },
    });
    for (final lang in ['en', 'ja']) {
      await AppLanguage.instance.select(lang);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookCatalogRow(
              item: item,
              installed: false,
              progress: null,
              onDownload: () {},
            ),
          ),
        ),
      );
      expect(
        find.text(lang == 'en' ? 'Episode 7 · 파도의 노래' : '第7話 · 파도의 노래'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  test(
    'locale resolution supports region variants and falls back to English',
    () {
      expect(AppLanguage.resolve([const Locale('ja', 'JP')]), 'ja');
      expect(AppLanguage.resolve([const Locale('ko', 'KR')]), 'ko');
      expect(
        AppLanguage.resolve([const Locale('fr'), const Locale('en', 'GB')]),
        'en',
      );
      expect(AppLanguage.resolve([const Locale('fr')]), 'en');
    },
  );
  test(
    'catalogs have matching placeholders and preserve literal arguments',
    () {
      final pattern = RegExp(r'\{\d+\}');
      for (final entry in messages.entries) {
        final expected = pattern.allMatches(entry.key).map((m) => m[0]).toSet();
        for (final language in ['en', 'ja']) {
          expect(entry.value[language], isNotEmpty, reason: entry.key);
          expect(
            pattern.allMatches(entry.value[language]!).map((m) => m[0]).toSet(),
            expected,
            reason: '${entry.key}: $language',
          );
        }
      }
      expect(
        translateMessage('en', '읽던 책: {0}', ['내 책 {1}']),
        'Currently reading: 내 책 {1}',
      );
    },
  );
  testWidgets(
    'device default, explicit selection, restart and return to automatic',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.binding.platformDispatcher.localesTestValue = [
        const Locale('ja', 'JP'),
      ];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await AppLanguage.instance.initialize();
      expect(AppLanguage.instance.code, 'ja');
      expect(AppLanguage.instance.selection, isNull);
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: AppLanguage.instance,
          builder: (context, _) => MaterialApp(
            locale: AppLanguage.instance.locale,
            supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              appBar: AppBar(actions: const [LanguageButton()]),
              body: Text(tr('나의 책')),
            ),
          ),
        ),
      );
      expect(find.text('自分の本'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('language-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('My books'), findsOneWidget);
      final restarted = AppLanguage();
      await restarted.initialize();
      expect(restarted.code, 'en');
      expect(restarted.selection, 'en');
      restarted.dispose();
      tester.binding.platformDispatcher.localesTestValue = [const Locale('ko')];
      await tester.pumpAndSettle();
      expect(AppLanguage.instance.code, 'en');
      await tester.tap(find.byKey(const ValueKey('language-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device language'));
      await tester.pumpAndSettle();
      expect(find.text('나의 책'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppLanguage.preferenceKey,
        ),
        isNull,
      );
      await AppLanguage.instance.select('ko');
    },
  );
}
