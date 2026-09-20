import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/domain/ad_state.dart';

class _ExpiringReward implements AdRepository {
  int reads = 0;
  @override
  Future<AdState> getState() async {
    reads++;
    return AdState(
      hiddenUntil: reads == 1
          ? DateTime.now().add(const Duration(seconds: 2))
          : null,
    );
  }

  @override
  Future<void> hideBannerForHours(int hours) async {}
}

void main() {
  testWidgets(
    'reward expiry refreshes an observed ad state without navigation',
    (tester) async {
      final repository = _ExpiringReward();
      final container = ProviderContainer(
        overrides: [adRepositoryProvider.overrideWithValue(repository)],
      );
      final subscription = container.listen(adStateProvider, (_, __) {});
      await tester.pump();
      expect(
        container.read(adStateProvider).requireValue.isBannerHidden,
        isTrue,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(repository.reads, 2);
      expect(
        container.read(adStateProvider).requireValue.isBannerHidden,
        isFalse,
      );
      subscription.close();
      container.dispose();
    },
  );
}
