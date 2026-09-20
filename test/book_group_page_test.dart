import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/book_group_page.dart';
import 'package:koofy_reader/features/library/presentation/widgets/book_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_page_test.dart' as shelf_test;

void main() {
  late BookGroupRepository repository;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repository = BookGroupRepository(SharedPrefsLocalStorage());
  });
  Future<void> create() async =>
      repository.create('백 편씩 모은 소설', ['b0', 'b1', 'b2']);
  Future<void> openGroup(WidgetTester tester) async {
    final group = (await repository.load()).single;
    final tile = find.byKey(ValueKey(group.id));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(tile);
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(BookCover)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'create from menu hides individual shelf entries and opens members',
    (tester) async {
      await shelf_test.pumpLibrary(
        tester,
        books: shelf_test.demoBooks.take(3).toList(),
        states: () async => {},
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('책 묶음 만들기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '묶음 이름'), '소설 묶음');
      await tester.tap(find.byKey(const ValueKey('select-b0')));
      await tester.tap(find.byKey(const ValueKey('select-b1')));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '2권 묶기'));
      await tester.pumpAndSettle();
      expect(find.byType(BookTile), findsNWidgets(2));
      expect(find.text('2권 묶음'), findsOneWidget);
      await openGroup(tester);
      expect(find.byKey(const ValueKey('group-book-b0')), findsOneWidget);
      expect(find.byKey(const ValueKey('group-book-b1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('group resumes the original most recently read book', (
    tester,
  ) async {
    await tester.runAsync(create);
    final routes = <RouteSettings>[];
    await shelf_test.pumpLibrary(
      tester,
      books: shelf_test.demoBooks.take(3).toList(),
      routes: routes,
    );
    await tester.pumpAndSettle();
    await openGroup(tester);
    await tester.tap(find.byKey(const ValueKey('group-continue')));
    await tester.pumpAndSettle();
    expect((routes.last.arguments as Book).id, 'b0');
    expect(
      (routes.last.arguments as Book).assetPath,
      shelf_test.demoBooks.first.assetPath,
    );
  });
  testWidgets('take out, undo, dissolve, undo preserve members', (
    tester,
  ) async {
    await tester.runAsync(create);
    await shelf_test.pumpLibrary(
      tester,
      books: shelf_test.demoBooks.take(3).toList(),
    );
    await tester.pumpAndSettle();
    await openGroup(tester);
    await tester.tap(find.byTooltip('작은 생활 더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('묶음에서 꺼내기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-book-b1')), findsNothing);
    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-book-b1')), findsOneWidget);
    await tester.tap(find.byTooltip('묶음 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('묶음 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '묶음 해제'));
    await tester.pumpAndSettle();
    expect(find.text('묶음이 해제되었습니다.'), findsOneWidget);
    await tester.tap(find.text('실행 취소'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-book-b0')), findsOneWidget);
    expect((await repository.load()).single.bookIds, ['b0', 'b1', 'b2']);
  });
  testWidgets(
    'search finds a group by member title and reading filters aggregate',
    (tester) async {
      await tester.runAsync(create);
      await shelf_test.pumpLibrary(
        tester,
        books: shelf_test.demoBooks.take(4).toList(),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('서재 검색'), findsNothing);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '작은 생활');
      await tester.pumpAndSettle();
      expect(find.byType(BookTile), findsOneWidget);
      expect(
        tester.widget<BookTile>(find.byType(BookTile)).book.title,
        '백 편씩 모은 소설',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, '읽는 중'));
      await tester.pumpAndSettle();
      expect(find.byType(BookTile), findsOneWidget);
    },
  );
  testWidgets('drop onto a book opens confirmation with both books selected', (
    tester,
  ) async {
    await shelf_test.pumpLibrary(
      tester,
      books: shelf_test.demoBooks.take(3).toList(),
      states: () async => {},
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('b0')));
    final source = tester.getCenter(
      find.descendant(
        of: find.byKey(const ValueKey('b0')),
        matching: find.byType(BookCover),
      ),
    );
    final target = tester.getCenter(
      find.descendant(
        of: find.byKey(const ValueKey('b1')),
        matching: find.byType(BookCover),
      ),
    );
    final gesture = await tester.startGesture(source);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '2권 묶기'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(await repository.load(), isEmpty);
  });
  testWidgets('add to an existing group and reorder its books', (tester) async {
    await tester.runAsync(() async {
      await repository.create('소설 묶음', ['b0', 'b1']);
    });
    await shelf_test.pumpLibrary(
      tester,
      books: shelf_test.demoBooks.take(3).toList(),
      states: () async => {},
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('밤의 도서관 더보기'));
    await tester.tap(find.byTooltip('밤의 도서관 더보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('묶음에 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '소설 묶음'));
    await tester.pumpAndSettle();
    expect((await repository.load()).single.bookIds, ['b0', 'b1', 'b2']);
    await openGroup(tester);
    final handles = find.byType(ReorderableDragStartListener);
    await tester.drag(handles.first, const Offset(0, 175));
    await tester.pumpAndSettle();
    expect((await repository.load()).single.bookIds.last, 'b0');
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 700), const Size(840, 900)]) {
    testWidgets('group detail fits $size with large text', (tester) async {
      await tester.runAsync(create);
      await shelf_test.pumpLibrary(
        tester,
        size: size,
        scale: 2,
        books: shelf_test.demoBooks.take(3).toList(),
      );
      await tester.pumpAndSettle();
      await openGroup(tester);
      expect(find.byType(BookGroupPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
