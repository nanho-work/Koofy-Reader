import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/catalog/presentation/promotion_carousel.dart';

void main() {
  for (final width in [320.0, 674.0, 1040.0]) {
    testWidgets('manual promotion paging at $width', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PromotionCarousel(
              cards: [
                Center(child: Text('First')),
                Center(child: Text('Second')),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 10));
      final page = tester.widget<PageView>(find.byType(PageView));
      expect(page.controller!.page, 0);
      expect(page.controller!.viewportFraction, 1);
      await tester.drag(find.byType(PageView), Offset(-width * .8, 0));
      await tester.pumpAndSettle();
      expect(page.controller!.page, 1);
      expect(
        tester.getRect(find.text('Second')).right,
        lessThanOrEqualTo(width),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
