import 'package:flutter_test/flutter_test.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'package:koofy_reader/features/ads/data/rewarded_ad_service.dart';

class _Ad extends LevelPlayRewardedAd {
  _Ad() : super(adUnitId: 'test');
  int disposals = 0;
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  final info = LevelPlayAdInfo.fromMap({
    for (final key in [
      'adId',
      'adUnitId',
      'adUnitName',
      'adFormat',
      'placementName',
      'auctionId',
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
    'revenue': 0.0,
  });
  final reward = LevelPlayReward(name: 'hide_ads', amount: 1);
  test(
    'reward after close is persisted once, including duplicate callback',
    () async {
      var grants = 0;
      final ad = _Ad();
      final attempt = RewardAttempt(
        ad: ad,
        onReward: () async {
          grants++;
        },
      );
      attempt.onAdClosed(info);
      expect(await attempt.closed.future, false);
      expect(grants, 0);
      attempt.onAdRewarded(reward, info);
      attempt.onAdRewarded(reward, info);
      await Future<void>.delayed(Duration.zero);
      expect(grants, 1);
      expect(ad.disposals, 1);
    },
  );
  test('reward before close settles success after persistence', () async {
    var grants = 0;
    final attempt = RewardAttempt(
      ad: _Ad(),
      onReward: () async {
        grants++;
      },
    );
    attempt.onAdRewarded(reward, info);
    attempt.onAdClosed(info);
    expect(await attempt.closed.future, true);
    expect(grants, 1);
  });
  test(
    'closed without reward never grants and a new attempt cannot consume a late reward',
    () async {
      var first = 0;
      var second = 0;
      final a = RewardAttempt(
        ad: _Ad(),
        onReward: () async {
          first++;
        },
      );
      final b = RewardAttempt(
        ad: _Ad(),
        onReward: () async {
          second++;
        },
      );
      a.onAdClosed(info);
      expect(await a.closed.future, false);
      expect(first, 0);
      a.onAdRewarded(reward, info);
      await Future<void>.delayed(Duration.zero);
      expect(first, 1);
      expect(second, 0);
      await b.dispose();
    },
  );
}
