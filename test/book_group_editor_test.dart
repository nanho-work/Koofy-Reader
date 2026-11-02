import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/book_group_editor.dart';

void main() {
  for (final language in ['ko', 'en', 'ja']) {
    testWidgets('bulk controls fit narrow screen with large $language text', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.instance.select(language);
      addTearDown(() => AppLanguage.instance.select('ko'));
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: BookGroupEditor(
            creating: false,
            books: [
              for (var i = 0; i < 3; i++)
                Book.asset(
                  id: '$i',
                  title: '$i',
                  author: '',
                  description: '',
                  assetPath: '$i',
                ),
            ],
          ),
        ),
      );
      await tester.tap(find.text(tr('전체 선택')));
      await tester.pump();
      expect(find.text(tr('{0}권 선택', [3])), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  final books = [
    for (final title in ['소설 10화', '소설 2화', '다른 책'])
      Book.asset(
        id: title,
        title: title,
        author: '',
        description: '',
        assetPath: title,
      ),
  ];
  testWidgets(
    'selecting all search results preserves hidden selections and applies chosen order',
    (tester) async {
      GroupSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<GroupSelection>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          BookGroupEditor(books: books, creating: false),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체 선택'));
      await tester.pump();
      expect(find.text('3권 선택'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '소설');
      await tester.pump();
      await tester.tap(find.text('검색 결과 선택 해제'));
      await tester.pump();
      expect(find.text('1권 선택'), findsOneWidget);
      await tester.tap(find.text('검색 결과 전체 선택'));
      await tester.pump();
      await tester.tap(find.byType(PopupMenuButton<bool>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<bool> && widget.value == true,
        ),
      );
      await tester.pumpAndSettle();
      final tiles = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .toList();
      expect((tiles.first.title as Text).data, '소설 10화');
      await tester.tap(find.text('3권 추가'));
      await tester.pumpAndSettle();
      expect(result!.ids, ['소설 10화', '소설 2화', '다른 책']);
    },
  );

  testWidgets('300 books can be selected in one action at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: BookGroupEditor(
          creating: false,
          books: [
            for (var i = 0; i < 300; i++)
              Book.asset(
                id: '$i',
                title: '$i화',
                author: '',
                description: '',
                assetPath: '$i',
              ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('전체 선택'));
    await tester.pump();
    expect(find.text('300권 선택'), findsOneWidget);
    expect(find.text('300권 추가'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('전체 선택 해제'));
    await tester.pump();
    expect(find.text('0권 선택'), findsOneWidget);
  });
}
