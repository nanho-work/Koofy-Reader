enum ReaderNavigationCommand {
  none,
  singlePrevious,
  singleNext,
  doublePrevious,
  doubleNext,
}

class ReaderNavigationController {
  const ReaderNavigationController();

  ReaderNavigationCommand resolveTapCommand({
    required double dx,
    required double width,
    required bool doubleMode,
    required bool isSpreadPaginating,
    required bool isSpreadJumping,
    required bool isDoubleViewportSettling,
    double leftRatio = 0.5,
  }) {
    if (doubleMode &&
        (isSpreadPaginating || isSpreadJumping || isDoubleViewportSettling)) {
      return ReaderNavigationCommand.none;
    }

    final isPrevious = width > 0 ? dx <= width * leftRatio : false;
    if (doubleMode) {
      return isPrevious
          ? ReaderNavigationCommand.doublePrevious
          : ReaderNavigationCommand.doubleNext;
    }
    return isPrevious
        ? ReaderNavigationCommand.singlePrevious
        : ReaderNavigationCommand.singleNext;
  }
}
