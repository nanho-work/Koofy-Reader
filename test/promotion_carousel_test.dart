import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/catalog/presentation/promotion_carousel.dart';

void main() {
  for (final width in [320.0, 674.0, 1040.0]) {
    testWidgets('promotion paging pauses for touch and loops at $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PromotionCarousel(
              cards: [
                Center(child: Text('First')),
                Center(child: Text('Second')),
                Center(child: Text('Third')),
              ],
            ),
          ),
        ),
      );
      final view = find.byType(PageView);
      final controller = tester.widget<PageView>(view).controller!;
      final first = controller.initialPage;
      expect(controller.page, first);
      expect(controller.viewportFraction, lessThan(1));
      final touch = await tester.startGesture(tester.getCenter(view));
      await tester.pump(const Duration(seconds: 8));
      expect(controller.page, first);
      await touch.up();
      await tester.pump(const Duration(milliseconds: 3499));
      expect(controller.page, first);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(controller.page, first + 1);
      await tester.drag(view, Offset(-width * .35, 0));
      await tester.pumpAndSettle();
      expect(controller.page, first + 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
