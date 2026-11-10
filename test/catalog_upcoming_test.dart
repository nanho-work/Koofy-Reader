import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/core/widgets/episode_shelf.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/book_catalog_row.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_shelf.dart';
import 'helpers/catalog_fixture.dart';
import 'library_page_test.dart' show pumpLibrary;

void main() {
  testWidgets(
    'scheduled chapter retains title and date but cannot download or open',
    (tester) async {
      await initializeDateFormatting('ko');
      final json = Map<String, dynamic>.from(catalogFixture(1).json)
        ..['upcoming'] = true
        ..['releaseAt'] = '2099-11-04T09:00:00+09:00';
      json['assets'] = {'cover': (json['assets'] as Map)['cover']};
      final item = CatalogItem.fromJson(json);
      var activated = false;
      await pumpLibrary(
        tester,
        rootPage: Scaffold(
          body: SizedBox(
            width: 140,
            child: BookCatalogRow(
              item: item,
              installed: false,
              episodeLayout: true,
              progress: null,
              onDownload: () => activated = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(item.title));
      await tester.pumpAndSettle();
      expect(activated, isFalse);
      expect(find.byType(FilledButton), findsNothing);
      final caption = find.byType(EpisodeCoverCaption);
      expect(
        find.descendant(of: caption, matching: find.text(item.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: caption,
          matching: find.textContaining(RegExp(r'\d{2}:\d{2} 공개$')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final language in ['ko', 'en', 'ja']) {
    for (final width in [320.0, 900.0]) {
      testWidgets(
        'scheduled dates and installed badges fit large text $language/$width',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          await AppLanguage.instance.initialize();
          await AppLanguage.instance.select(language);
          addTearDown(() => AppLanguage.instance.select('ko'));
          final json = Map<String, dynamic>.from(catalogFixture(1).json)
            ..['upcoming'] = true
            ..['releaseAt'] = '2099-11-04T09:00:00+09:00';
          json['assets'] = {'cover': (json['assets'] as Map)['cover']};
          final scheduled = CatalogItem.fromJson(json);
          final controller = ScrollController();
          await pumpLibrary(
            tester,
            size: Size(width, 900),
            scale: 2.5,
            rootPage: Scaffold(
              body: CatalogShelfList(
                controller: controller,
                padding: const EdgeInsets.all(16),
                itemCount: 3,
                episodeLayout: true,
                itemBuilder: (context, index) => index == 0
                    ? const Text('Books')
                    : CatalogShelfCard(
                        item: index == 1 ? scheduled : catalogFixture(2),
                        installed: index == 2,
                        episodeLayout: true,
                        onTap: () {},
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        },
      );
    }
  }
}
