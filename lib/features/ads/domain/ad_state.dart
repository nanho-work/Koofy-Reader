class AdState {
  const AdState({required this.hiddenUntil});

  final DateTime? hiddenUntil;

  bool get isBannerHidden {
    final until = hiddenUntil;
    if (until == null) {
      return false;
    }
    return DateTime.now().isBefore(until);
  }
}
