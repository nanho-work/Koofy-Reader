import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/core/services/reader_progress_coordinator.dart';

void main() {
  const service = ReaderProgressCoordinator();

  test('hasPendingMutation reflects coordinator and spread state', () {
    const state = ReaderProgressCoordinatorState(pendingAnchorOffset: 10);

    expect(
      service.hasPendingMutation(
        state: state,
        isSpreadPaginating: false,
        isSpreadJumping: false,
      ),
      isTrue,
    );
    expect(
      service.hasPendingMutation(
        state: const ReaderProgressCoordinatorState(),
        isSpreadPaginating: true,
        isSpreadJumping: false,
      ),
      isTrue,
    );
    expect(
      service.hasPendingMutation(
        state: const ReaderProgressCoordinatorState(),
        isSpreadPaginating: false,
        isSpreadJumping: false,
      ),
      isFalse,
    );
  });

  test('stableProgressOffset prefers pending and mode anchors', () {
    const state = ReaderProgressCoordinatorState(
      pendingAnchorOffset: 50,
      pendingModeAnchorOffset: 80,
    );

    expect(
      service.stableProgressOffset(
        state: state,
        restoredContentOffset: 120,
        lastKnownContentOffset: 200,
        contentLength: 500,
      ),
      50,
    );

    expect(
      service.stableProgressOffset(
        state: const ReaderProgressCoordinatorState(
          pendingModeAnchorOffset: 80,
        ),
        restoredContentOffset: 120,
        lastKnownContentOffset: 200,
        contentLength: 500,
      ),
      80,
    );
  });

  test('preferredDoubleAnchorOffset falls back to stable then last known', () {
    expect(
      service.preferredDoubleAnchorOffset(
        state: const ReaderProgressCoordinatorState(),
        restoredContentOffset: null,
        stableAnchorOffset: 140,
        lastKnownContentOffset: 220,
        contentLength: 500,
      ),
      140,
    );

    expect(
      service.preferredDoubleAnchorOffset(
        state: const ReaderProgressCoordinatorState(),
        restoredContentOffset: null,
        stableAnchorOffset: 0,
        lastKnownContentOffset: 220,
        contentLength: 500,
      ),
      220,
    );
  });

  test('beginModeTransition stores pending target state', () {
    final result = service.beginModeTransition(
      state: const ReaderProgressCoordinatorState(),
      targetDoubleMode: true,
      anchorOffset: 144,
      preserveRawPendingSingleAnchor: false,
      contentLength: 500,
    );

    expect(result.anchorOffset, 144);
    expect(result.targetDoubleMode, isTrue);
    expect(result.state.isModeTransitioning, isTrue);
    expect(result.state.modeTransitionTarget, isTrue);
    expect(result.state.pendingModeAnchorOffset, 144);
  });

  test('resolveModeTransitionApply materializes anchor as pending offset', () {
    final result = service.resolveModeTransitionApply(
      state: const ReaderProgressCoordinatorState(
        isModeTransitioning: true,
        modeTransitionTarget: false,
        pendingModeAnchorOffset: 212,
        preserveRawPendingSingleAnchor: true,
      ),
      fallbackTargetDoubleMode: true,
      fallbackAnchorOffset: 99,
      contentLength: 500,
    );

    expect(result.targetDoubleMode, isFalse);
    expect(result.anchorOffset, 212);
    expect(result.state.pendingAnchorOffset, 212);
    expect(result.state.isModeTransitioning, isFalse);
    expect(result.state.modeTransitionTarget, isNull);
    expect(result.state.pendingModeAnchorOffset, isNull);
    expect(result.state.preserveRawPendingSingleAnchor, isTrue);
  });

  test('deferSingleJump stores pending anchor and clears restored flag', () {
    final result = service.deferSingleJump(
      state: const ReaderProgressCoordinatorState(restoredScrollApplied: true),
      targetOffset: 88,
      contentLength: 500,
    );

    expect(result.targetOffset, 88);
    expect(result.state.pendingAnchorOffset, 88);
    expect(result.state.restoredScrollApplied, isFalse);
  });

  test('applySingleJump marks restored scroll as applied', () {
    final result = service.applySingleJump(
      state: const ReaderProgressCoordinatorState(),
    );

    expect(result.state.restoredScrollApplied, isTrue);
  });

  test('defer/apply spread jump manages pending spread state', () {
    final deferred = service.deferSpreadJump(
      state: const ReaderProgressCoordinatorState(pendingAnchorOffset: 77),
      spreadJumpIndex: 6,
    );

    expect(deferred.state.pendingSpreadJumpIndex, 6);
    expect(deferred.spreadJumpIndex, 6);

    final applied = service.applySpreadJump(state: deferred.state);
    expect(applied.state.pendingSpreadJumpIndex, isNull);
    expect(applied.state.pendingAnchorOffset, isNull);
  });

  test(
    'beginDoubleRestore creates pending anchor once from restored progress',
    () {
      final result = service.beginDoubleRestore(
        state: const ReaderProgressCoordinatorState(),
        preferredAnchorOffset: 144,
        hasRestoredContentOffset: true,
        contentLength: 500,
      );

      expect(result.targetOffset, 144);
      expect(result.state.pendingAnchorOffset, 144);
      expect(result.state.restoredScrollApplied, isTrue);
    },
  );

  test('consumePendingSpreadJump clears only spread jump state', () {
    final result = service.consumePendingSpreadJump(
      state: const ReaderProgressCoordinatorState(
        pendingAnchorOffset: 77,
        pendingSpreadJumpIndex: 6,
      ),
    );

    expect(result.spreadJumpIndex, 6);
    expect(result.state.pendingSpreadJumpIndex, isNull);
    expect(result.state.pendingAnchorOffset, 77);
  });

  test('consumePendingSingleAnchor clears anchor and raw single flag', () {
    final result = service.consumePendingSingleAnchor(
      state: const ReaderProgressCoordinatorState(
        pendingAnchorOffset: 99,
        preserveRawPendingSingleAnchor: true,
      ),
    );

    expect(result.targetOffset, 99);
    expect(result.preserveRawSingleAnchor, isTrue);
    expect(result.state.pendingAnchorOffset, isNull);
    expect(result.state.preserveRawPendingSingleAnchor, isFalse);
  });
}
