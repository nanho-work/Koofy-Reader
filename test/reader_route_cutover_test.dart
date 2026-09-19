import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/presentation/native_reader_launch_page.dart';

void main() {
  testWidgets('both reader URLs construct only NativeReaderLaunchPage', (
    tester,
  ) async {
    final book = Book.asset(
      id: 'book',
      title: 'Book',
      author: '',
      description: '',
      assetPath: 'unused.txt',
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox).first);
    for (final name in [AppRoutes.reader, AppRoutes.nativeReader]) {
      final route =
          AppRouter.onGenerateRoute(RouteSettings(name: name, arguments: book))
              as MaterialPageRoute;
      expect(route.builder(context), isA<NativeReaderLaunchPage>());
    }
  });
}
