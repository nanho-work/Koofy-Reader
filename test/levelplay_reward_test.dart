import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'package:koofy_reader/features/ads/data/rewarded_ad_service.dart';

LevelPlayAdInfo info(String auction) => LevelPlayAdInfo.fromMap({
  for (final key in [
    'adId',
    'adUnitId',
    'adUnitName',
    'adFormat',
    'placementName',
    'country',
    'ab',
    'segmentName',
    'adNetwork',
    'instanceName',
    'instanceId',
    'precision',
    'encryptedCPM',
    'creativeId',
  ])
    key: 'test',
  'auctionId': auction,
  'revenue': 0.0,
});
final reward = LevelPlayReward(name: 'hide_ads', amount: 1);

class FakeRewardAd extends LevelPlayRewardedAd {
  FakeRewardAd() : super(adUnitId: 'test');
  late LevelPlayRewardedAdListener callbacks;
  int loads = 0, disposals = 0;
  @override
  void setListener(LevelPlayRewardedAdListener listener) {
    callbacks = listener;
  }

  @override
  Future<void> loadAd() async {
    loads++;
    callbacks.onAdLoaded(info('$loads'));
  }

  @override
  Future<bool> isAdReady() async => true;
  @override
  Future<void> showAd({String? placementName}) async {
    callbacks.onAdDisplayed(info('$loads'));
    callbacks.onAdClosed(info('$loads'));
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  test(
    'reward after close is persisted once, even during the next viewing',
    () async {
      var grants = 0;
      final callbacks = RewardCallbacks(() async {
        grants++;
      });
      final first = callbacks.begin();
      callbacks.onAdDisplayed(info('one'));
      callbacks.onAdClosed(info('one'));
      expect(await first.closed.future, false);
      final second = callbacks.begin();
      callbacks.onAdDisplayed(info('two'));
      callbacks.onAdRewarded(reward, info('one'));
      callbacks.onAdRewarded(reward, info('one'));
      callbacks.onAdClosed(info('one')); // Old close cannot settle the new UI.
      await Future<void>.delayed(Duration.zero);
      expect(grants, 1);
      expect(second.closed.isCompleted, false);
      callbacks.onAdClosed(info('two'));
      expect(await second.closed.future, false);
      callbacks.dispose();
    },
  );
  test('reward before close settles only after persistence succeeds', () async {
    final saved = Completer<void>();
    final callbacks = RewardCallbacks(() => saved.future);
    final attempt = callbacks.begin();
    callbacks.onAdDisplayed(info('one'));
    callbacks.onAdRewarded(reward, info('one'));
    callbacks.onAdClosed(info('one'));
    await Future<void>.delayed(Duration.zero);
    expect(attempt.closed.isCompleted, false);
    saved.complete();
    expect(await attempt.closed.future, true);
    callbacks.dispose();
  });
  test(
    'failed persistence does not grant success or poison later rewards',
    () async {
      var calls = 0;
      final callbacks = RewardCallbacks(() async {
        if (++calls == 1) throw StateError('disk full');
      });
      final first = callbacks.begin();
      callbacks.onAdDisplayed(info('one'));
      callbacks.onAdRewarded(reward, info('one'));
      callbacks.onAdClosed(info('one'));
      expect(await first.closed.future, false);
      final next = callbacks.begin();
      callbacks.onAdDisplayed(info('two'));
      callbacks.onAdRewarded(reward, info('two'));
      callbacks.onAdClosed(info('two'));
      expect(await next.closed.future, true);
      callbacks.dispose();
    },
  );
  test(
    '100 closes without reward reuse one native ad; late reward still works',
    () async {
      final ad = FakeRewardAd();
      var creations = 0, grants = 0;
      final service = RewardedAdService(
        initialize: () async => true,
        createAd: () {
          creations++;
          return ad;
        },
        onReward: () async {
          grants++;
        },
      );
      for (var i = 0; i < 100; i++) {
        expect(await service.show(), false);
      }
      expect(creations, 1);
      expect(ad.disposals, 0);
      expect(grants, 0);
      ad.callbacks.onAdRewarded(reward, info('1'));
      await Future<void>.delayed(Duration.zero);
      expect(grants, 1);
      service.dispose();
      expect(ad.disposals, 1);
    },
  );
}
