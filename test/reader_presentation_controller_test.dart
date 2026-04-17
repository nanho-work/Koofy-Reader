import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/application/controllers/reader_presentation_controller.dart';

void main() {
  const controller = ReaderPresentationController();

  test('shows footer ad only in single mode without pending mutation', () {
    final state = controller.build(
      requestedDoubleMode: false,
      hasPendingPositionMutation: false,
      hasQueryMatches: true,
    );

    expect(state.hasQueryMatches, isTrue);
    expect(state.shouldShowFooterAd, isTrue);
  });

  test('hides footer ad during double mode or pending mutation', () {
    final doubleState = controller.build(
      requestedDoubleMode: true,
      hasPendingPositionMutation: false,
      hasQueryMatches: false,
    );
    final pendingState = controller.build(
      requestedDoubleMode: false,
      hasPendingPositionMutation: true,
      hasQueryMatches: false,
    );

    expect(doubleState.shouldShowFooterAd, isFalse);
    expect(pendingState.shouldShowFooterAd, isFalse);
  });
}
