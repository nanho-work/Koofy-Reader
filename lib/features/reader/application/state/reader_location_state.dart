class ReaderLocationState {
  const ReaderLocationState({
    required this.singleContentOffset,
    required this.singleFocusOffset,
    required this.spreadStartIndex,
    required this.contentOffset,
    required this.stableAnchorOffset,
    required this.doublePageStartOffset,
  });

  final int singleContentOffset;
  final int singleFocusOffset;
  final int spreadStartIndex;
  final int contentOffset;
  final int stableAnchorOffset;
  final int? doublePageStartOffset;
}
