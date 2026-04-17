import 'package:koofy_reader/features/reader/application/state/reader_presentation_state.dart';

class ReaderPresentationController {
  const ReaderPresentationController();

  ReaderPresentationState build({
    required bool requestedDoubleMode,
    required bool hasPendingPositionMutation,
    required bool hasQueryMatches,
  }) {
    return ReaderPresentationState(
      hasQueryMatches: hasQueryMatches,
      shouldShowFooterAd: !requestedDoubleMode && !hasPendingPositionMutation,
    );
  }
}
