class ReaderModeTransitionRequest {
  const ReaderModeTransitionRequest({
    required this.targetDoubleMode,
    required this.anchorOffset,
    required this.preserveRawSingleAnchor,
    required this.delayMs,
  });

  final bool targetDoubleMode;
  final int anchorOffset;
  final bool preserveRawSingleAnchor;
  final int delayMs;
}

class ReaderModeTransitionService {
  const ReaderModeTransitionService();

  ReaderModeTransitionRequest? buildRequest({
    required bool requestedDoubleMode,
    required bool activeDoubleMode,
    required int preferredDoubleAnchorOffset,
    required int stableAnchorOffset,
    required int? pendingModeAnchorOffset,
    required int contentLength,
  }) {
    if (requestedDoubleMode == activeDoubleMode) {
      return null;
    }

    final anchor = requestedDoubleMode
        ? preferredDoubleAnchorOffset
        : (pendingModeAnchorOffset ?? stableAnchorOffset);

    return ReaderModeTransitionRequest(
      targetDoubleMode: requestedDoubleMode,
      anchorOffset: anchor.clamp(0, contentLength),
      preserveRawSingleAnchor: !requestedDoubleMode,
      delayMs: 0,
    );
  }

  bool hasPendingRequestedTransition({
    required bool requestedDoubleMode,
    required bool? modeTransitionTarget,
    required int? pendingModeAnchorOffset,
  }) {
    return modeTransitionTarget == requestedDoubleMode &&
        pendingModeAnchorOffset != null;
  }
}
