class ReaderProgressCoordinatorState {
  const ReaderProgressCoordinatorState({
    this.restoredScrollApplied = false,
    this.pendingAnchorOffset,
    this.pendingSpreadJumpIndex,
    this.isModeTransitioning = false,
    this.modeTransitionTarget,
    this.pendingModeAnchorOffset,
    this.preserveRawPendingSingleAnchor = false,
  });

  final bool restoredScrollApplied;
  final int? pendingAnchorOffset;
  final int? pendingSpreadJumpIndex;
  final bool isModeTransitioning;
  final bool? modeTransitionTarget;
  final int? pendingModeAnchorOffset;
  final bool preserveRawPendingSingleAnchor;

  ReaderProgressCoordinatorState copyWith({
    bool? restoredScrollApplied,
    int? pendingAnchorOffset,
    bool clearPendingAnchorOffset = false,
    int? pendingSpreadJumpIndex,
    bool clearPendingSpreadJumpIndex = false,
    bool? isModeTransitioning,
    bool? modeTransitionTarget,
    bool clearModeTransitionTarget = false,
    int? pendingModeAnchorOffset,
    bool clearPendingModeAnchorOffset = false,
    bool? preserveRawPendingSingleAnchor,
  }) {
    return ReaderProgressCoordinatorState(
      restoredScrollApplied:
          restoredScrollApplied ?? this.restoredScrollApplied,
      pendingAnchorOffset: clearPendingAnchorOffset
          ? null
          : (pendingAnchorOffset ?? this.pendingAnchorOffset),
      pendingSpreadJumpIndex: clearPendingSpreadJumpIndex
          ? null
          : (pendingSpreadJumpIndex ?? this.pendingSpreadJumpIndex),
      isModeTransitioning: isModeTransitioning ?? this.isModeTransitioning,
      modeTransitionTarget: clearModeTransitionTarget
          ? null
          : (modeTransitionTarget ?? this.modeTransitionTarget),
      pendingModeAnchorOffset: clearPendingModeAnchorOffset
          ? null
          : (pendingModeAnchorOffset ?? this.pendingModeAnchorOffset),
      preserveRawPendingSingleAnchor:
          preserveRawPendingSingleAnchor ?? this.preserveRawPendingSingleAnchor,
    );
  }
}

class ReaderModeTransitionStartResult {
  const ReaderModeTransitionStartResult({
    required this.state,
    required this.anchorOffset,
    required this.targetDoubleMode,
  });

  final ReaderProgressCoordinatorState state;
  final int anchorOffset;
  final bool targetDoubleMode;
}

class ReaderModeTransitionApplyResult {
  const ReaderModeTransitionApplyResult({
    required this.state,
    required this.anchorOffset,
    required this.targetDoubleMode,
  });

  final ReaderProgressCoordinatorState state;
  final int anchorOffset;
  final bool targetDoubleMode;
}

class ReaderJumpStateResult {
  const ReaderJumpStateResult({
    required this.state,
    this.targetOffset,
    this.spreadJumpIndex,
  });

  final ReaderProgressCoordinatorState state;
  final int? targetOffset;
  final int? spreadJumpIndex;
}

class ReaderPendingActionResult {
  const ReaderPendingActionResult({
    required this.state,
    this.targetOffset,
    this.spreadJumpIndex,
    this.preserveRawSingleAnchor = false,
  });

  final ReaderProgressCoordinatorState state;
  final int? targetOffset;
  final int? spreadJumpIndex;
  final bool preserveRawSingleAnchor;
}

class ReaderProgressCoordinator {
  const ReaderProgressCoordinator();

  bool hasPendingMutation({
    required ReaderProgressCoordinatorState state,
    required bool isSpreadPaginating,
    required bool isSpreadJumping,
  }) {
    return state.isModeTransitioning ||
        isSpreadPaginating ||
        isSpreadJumping ||
        state.pendingAnchorOffset != null ||
        state.pendingSpreadJumpIndex != null ||
        state.modeTransitionTarget != null;
  }

  int stableProgressOffset({
    required ReaderProgressCoordinatorState state,
    required int? restoredContentOffset,
    required int lastKnownContentOffset,
    required int contentLength,
  }) {
    final preferred =
        state.pendingAnchorOffset ??
        state.pendingModeAnchorOffset ??
        restoredContentOffset ??
        lastKnownContentOffset;
    return preferred.clamp(0, contentLength);
  }

  int preferredDoubleAnchorOffset({
    required ReaderProgressCoordinatorState state,
    required int? restoredDoublePageStartOffset,
    required int? restoredContentOffset,
    required int stableAnchorOffset,
    required int lastKnownContentOffset,
    required int contentLength,
  }) {
    if (state.pendingAnchorOffset != null) {
      return state.pendingAnchorOffset!.clamp(0, contentLength);
    }
    if (state.pendingModeAnchorOffset != null) {
      return state.pendingModeAnchorOffset!.clamp(0, contentLength);
    }
    if (restoredDoublePageStartOffset != null) {
      return restoredDoublePageStartOffset.clamp(0, contentLength);
    }
    final stable = stableAnchorOffset.clamp(0, contentLength);
    if (stable > 0 || contentLength == 0) {
      return stable;
    }
    if (restoredContentOffset != null) {
      return restoredContentOffset.clamp(0, contentLength);
    }
    return lastKnownContentOffset.clamp(0, contentLength);
  }

  ReaderModeTransitionStartResult beginModeTransition({
    required ReaderProgressCoordinatorState state,
    required bool targetDoubleMode,
    required int anchorOffset,
    required bool preserveRawPendingSingleAnchor,
    required int contentLength,
  }) {
    final clampedAnchor = anchorOffset.clamp(0, contentLength);
    return ReaderModeTransitionStartResult(
      anchorOffset: clampedAnchor,
      targetDoubleMode: targetDoubleMode,
      state: state.copyWith(
        pendingModeAnchorOffset: clampedAnchor,
        modeTransitionTarget: targetDoubleMode,
        preserveRawPendingSingleAnchor: preserveRawPendingSingleAnchor,
        isModeTransitioning: true,
      ),
    );
  }

  ReaderModeTransitionApplyResult resolveModeTransitionApply({
    required ReaderProgressCoordinatorState state,
    required bool fallbackTargetDoubleMode,
    required int fallbackAnchorOffset,
    required int contentLength,
  }) {
    final targetDoubleMode =
        state.modeTransitionTarget ?? fallbackTargetDoubleMode;
    final anchorOffset = (state.pendingModeAnchorOffset ?? fallbackAnchorOffset)
        .clamp(0, contentLength);
    return ReaderModeTransitionApplyResult(
      anchorOffset: anchorOffset,
      targetDoubleMode: targetDoubleMode,
      state: state.copyWith(
        pendingAnchorOffset: anchorOffset,
        isModeTransitioning: false,
        clearModeTransitionTarget: true,
        clearPendingModeAnchorOffset: true,
      ),
    );
  }

  ReaderJumpStateResult deferSingleJump({
    required ReaderProgressCoordinatorState state,
    required int targetOffset,
    required int contentLength,
  }) {
    final clamped = targetOffset.clamp(0, contentLength);
    return ReaderJumpStateResult(
      targetOffset: clamped,
      state: state.copyWith(
        pendingAnchorOffset: clamped,
        restoredScrollApplied: false,
      ),
    );
  }

  ReaderJumpStateResult applySingleJump({
    required ReaderProgressCoordinatorState state,
  }) {
    return ReaderJumpStateResult(
      state: state.copyWith(restoredScrollApplied: true),
    );
  }

  ReaderJumpStateResult deferSpreadJump({
    required ReaderProgressCoordinatorState state,
    required int spreadJumpIndex,
  }) {
    return ReaderJumpStateResult(
      spreadJumpIndex: spreadJumpIndex,
      state: state.copyWith(pendingSpreadJumpIndex: spreadJumpIndex),
    );
  }

  ReaderJumpStateResult applySpreadJump({
    required ReaderProgressCoordinatorState state,
  }) {
    return ReaderJumpStateResult(
      state: state.copyWith(
        clearPendingAnchorOffset: true,
        clearPendingSpreadJumpIndex: true,
      ),
    );
  }

  ReaderProgressCoordinatorState clearConsumedPendingAnchor(
    ReaderProgressCoordinatorState state,
  ) {
    return state.copyWith(clearPendingAnchorOffset: true);
  }

  ReaderProgressCoordinatorState resolveRestoredOffset({
    required ReaderProgressCoordinatorState state,
    required int? restoredContentOffset,
    required bool isDoubleActive,
  }) {
    if (state.restoredScrollApplied) {
      return state;
    }
    if (restoredContentOffset == null) {
      return state.copyWith(restoredScrollApplied: true);
    }
    if (isDoubleActive) {
      return state;
    }
    return state;
  }

  ReaderPendingActionResult beginDoubleRestore({
    required ReaderProgressCoordinatorState state,
    required int preferredAnchorOffset,
    required bool hasRestoredContentOffset,
    required int contentLength,
  }) {
    if (state.restoredScrollApplied || !hasRestoredContentOffset) {
      return ReaderPendingActionResult(state: state);
    }
    final target = preferredAnchorOffset.clamp(0, contentLength);
    return ReaderPendingActionResult(
      targetOffset: target,
      state: state.copyWith(
        pendingAnchorOffset: target,
        restoredScrollApplied: true,
      ),
    );
  }

  ReaderPendingActionResult consumePendingSpreadJump({
    required ReaderProgressCoordinatorState state,
  }) {
    return ReaderPendingActionResult(
      spreadJumpIndex: state.pendingSpreadJumpIndex,
      state: state.copyWith(clearPendingSpreadJumpIndex: true),
    );
  }

  ReaderPendingActionResult consumePendingSingleAnchor({
    required ReaderProgressCoordinatorState state,
  }) {
    return ReaderPendingActionResult(
      targetOffset: state.pendingAnchorOffset,
      preserveRawSingleAnchor: state.preserveRawPendingSingleAnchor,
      state: state.copyWith(
        clearPendingAnchorOffset: true,
        preserveRawPendingSingleAnchor: false,
      ),
    );
  }
}
