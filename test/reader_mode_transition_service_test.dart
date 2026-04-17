import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/core/services/reader_mode_transition_service.dart';

void main() {
  const service = ReaderModeTransitionService();

  test('buildRequest returns null when mode does not change', () {
    final request = service.buildRequest(
      requestedDoubleMode: false,
      activeDoubleMode: false,
      preferredDoubleAnchorOffset: 100,
      stableAnchorOffset: 200,
      pendingModeAnchorOffset: null,
      contentLength: 1000,
    );

    expect(request, isNull);
  });

  test(
    'buildRequest uses preferred double anchor when entering double mode',
    () {
      final request = service.buildRequest(
        requestedDoubleMode: true,
        activeDoubleMode: false,
        preferredDoubleAnchorOffset: 444,
        stableAnchorOffset: 200,
        pendingModeAnchorOffset: 111,
        contentLength: 1000,
      );

      expect(request, isNotNull);
      expect(request!.targetDoubleMode, isTrue);
      expect(request.anchorOffset, 444);
      expect(request.delayMs, 0);
      expect(request.preserveRawSingleAnchor, isFalse);
    },
  );

  test(
    'buildRequest uses pending/stable anchor when returning to single mode',
    () {
      final request = service.buildRequest(
        requestedDoubleMode: false,
        activeDoubleMode: true,
        preferredDoubleAnchorOffset: 444,
        stableAnchorOffset: 200,
        pendingModeAnchorOffset: 333,
        contentLength: 1000,
      );

      expect(request, isNotNull);
      expect(request!.targetDoubleMode, isFalse);
      expect(request.anchorOffset, 333);
      expect(request.delayMs, 0);
      expect(request.preserveRawSingleAnchor, isTrue);
    },
  );

  test('hasPendingRequestedTransition matches pending target mode', () {
    final matched = service.hasPendingRequestedTransition(
      requestedDoubleMode: true,
      modeTransitionTarget: true,
      pendingModeAnchorOffset: 12,
    );
    final unmatched = service.hasPendingRequestedTransition(
      requestedDoubleMode: false,
      modeTransitionTarget: true,
      pendingModeAnchorOffset: 12,
    );

    expect(matched, isTrue);
    expect(unmatched, isFalse);
  });
}
