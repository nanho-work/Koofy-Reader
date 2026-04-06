import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:koofy_reader/features/ads/config/admob_ids.dart';

final rewardedAdServiceProvider = Provider<RewardedAdService>((ref) {
  final service = RewardedAdService()..load();
  ref.onDispose(service.dispose);
  return service;
});

class RewardedAdService {
  RewardedAd? _rewardedAd;
  bool _isLoading = false;

  bool get isReady => _rewardedAd != null;

  Future<void> load() async {
    if (_isLoading || _rewardedAd != null) return;

    final unitId = AdMobIds.rewardedUnitId;
    if (unitId == null || unitId.isEmpty) return;

    _isLoading = true;
    final completer = Completer<void>();

    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        onAdFailedToLoad: (_) {
          _isLoading = false;
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    await completer.future;
  }

  Future<bool?> show() async {
    if (_rewardedAd == null) {
      await load();
      if (_rewardedAd == null) {
        return null;
      }
    }

    final ad = _rewardedAd;
    if (ad == null) {
      return null;
    }
    _rewardedAd = null;

    final completer = Completer<bool>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(earned);
        }
        unawaited(load());
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        unawaited(load());
      },
    );

    ad.show(
      onUserEarnedReward: (_, __) {
        earned = true;
      },
    );

    return completer.future;
  }

  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }
}
