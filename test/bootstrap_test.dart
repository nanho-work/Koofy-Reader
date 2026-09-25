import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/app/bootstrap.dart';

void main() {
  testWidgets(
    'failed startup is visible and retryable without opening library early',
    (tester) async {
      final first = Completer<void>();
      var starts = 0;
      await tester.pumpWidget(
        ReaderBootstrap(
          initialize: () {
            starts++;
            return starts == 1 ? first.future : Future<void>.value();
          },
          child: const MaterialApp(home: Text('서재 준비 완료')),
        ),
      );
      expect(find.text('서재 준비 완료'), findsNothing);
      first.completeError(StateError('migration failed'));
      await tester.pumpAndSettle();
      expect(find.text('다시 시도'), findsOneWidget);
      expect(find.text('서재 준비 완료'), findsNothing);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(starts, 2);
      expect(find.text('서재 준비 완료'), findsOneWidget);
    },
  );
}
