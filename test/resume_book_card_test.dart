import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/widgets/resume_book_card.dart';

void main() {
  testWidgets(
    'hint finishes three pulses and stays hidden after the cover is used',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var opened = 0;
      final book = Book.asset(
        id: 'hint',
        title: '테스트',
        author: '',
        description: '',
        assetPath: 'sample.txt',
      );
      Widget app() => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 172,
            child: ResumeBookCard(book: book, onTap: () => opened++),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pump();
      expect(find.text('표지를 누르면 이어 읽어요'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.tap(find.byKey(const ValueKey('continue-reading-button')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('표지를 누르면 이어 읽어요'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          ResumeBookCard.hintUsedKey,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('표지를 누르면 이어 읽어요'), findsNothing);
    },
  );
}
