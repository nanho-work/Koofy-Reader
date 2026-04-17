import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/application/controllers/reader_location_controller.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';

void main() {
  const controller = ReaderLocationController();

  test('build prefers pinned offset for double content and stable anchor', () {
    const pages = PaginatedText(
      source: 'abcdefghij',
      ranges: [
        TextPageRange(start: 0, end: 2),
        TextPageRange(start: 2, end: 4),
        TextPageRange(start: 4, end: 6),
        TextPageRange(start: 6, end: 8),
      ],
    );

    final state = controller.build(
      content: pages.source,
      isDoubleActive: true,
      singlePainter: null,
      hasSingleScrollClients: false,
      singleScrollOffset: 0,
      singleMaxScrollExtent: 0,
      singleViewportHeight: 0,
      spreadPages: pages,
      spreadIndex: 2,
      isSpreadJumping: false,
      hasSpreadClients: true,
      spreadViewportExtent: 633,
      spreadScrollOffset: 633,
      lastKnownContentOffset: 1,
      pendingAnchorOffset: null,
      restoredContentOffset: 3,
      restoredDoublePageStartOffset: null,
      pinnedDoubleContentOffset: 5,
    );

    expect(state.spreadStartIndex, 2);
    expect(state.contentOffset, 5);
    expect(state.stableAnchorOffset, 5);
    expect(state.doublePageStartOffset, 4);
  });

  test(
    'build falls back to restored double page start without spread pages',
    () {
      final state = controller.build(
        content: 'abcdefghij',
        isDoubleActive: true,
        singlePainter: null,
        hasSingleScrollClients: false,
        singleScrollOffset: 0,
        singleMaxScrollExtent: 0,
        singleViewportHeight: 0,
        spreadPages: null,
        spreadIndex: 0,
        isSpreadJumping: false,
        hasSpreadClients: false,
        spreadViewportExtent: 0,
        spreadScrollOffset: 0,
        lastKnownContentOffset: 1,
        pendingAnchorOffset: 2,
        restoredContentOffset: 3,
        restoredDoublePageStartOffset: 7,
        pinnedDoubleContentOffset: null,
      );

      expect(state.doublePageStartOffset, 7);
      expect(state.stableAnchorOffset, 2);
    },
  );
}
