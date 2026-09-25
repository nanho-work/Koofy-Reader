import 'dart:async';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import '../config/levelplay_ids.dart';
import 'ad_repository.dart';
import 'levelplay_service.dart';

final rewardedAdServiceProvider = Provider<RewardedAdService>((ref) {
  final repository = ref.watch(adRepositoryProvider);
  final service = RewardedAdService(
    onReward: () async {
      // A late callback must never shorten an existing entitlement.
      if (!(await repository.getState()).isBannerHidden) {
        await repository.hideBannerForHours(AppConstants.adRewardHours);
      }
      ref.invalidate(adStateProvider);
      try {
        await updateNativeReaderAdHiddenUntil(
          (await repository.getState()).hiddenUntil?.millisecondsSinceEpoch,
        );
      } catch (error) {
        debugPrint('Native reward refresh unavailable: $error');
      }
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

class RewardedAdService {
  RewardedAdService({
    Future<void> Function()? onReward,
    Future<bool> Function()? initialize,
    LevelPlayRewardedAd Function()? createAd,
  }) : _initialize = initialize ?? LevelPlayService.instance.initialize,
       _createAd =
           createAd ??
           (() => LevelPlayRewardedAd(adUnitId: LevelPlayIds.rewarded)),
       _callbacks = RewardCallbacks(onReward ?? _noop);
  static Future<void> _noop() async {}
  final Future<bool> Function() _initialize;
  final LevelPlayRewardedAd Function() _createAd;
  final RewardCallbacks _callbacks;
  LevelPlayRewardedAd? _ad;
  bool _showing = false;
  bool _disposed = false;

  Future<bool?> show() async {
    if (_showing || _disposed) return null;
    _showing = true;
    try {
      if (!await _initialize() || _disposed) return null;
      final ad = _ad ??= _createAd()..setListener(_callbacks);
      final attempt = _callbacks.begin();
      await ad.loadAd();
      if (!await attempt.loaded.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      )) {
        _callbacks.finish(attempt);
        // Keep the shared listener/ad alive for delayed rewards from a previous
        // impression. A load failure creates no additional native ad object.
        return null;
      }
      if (_disposed || !await ad.isAdReady()) {
        _callbacks.finish(attempt);
        return null;
      }
      await ad.showAd();
      return await attempt.closed.future;
    } catch (error) {
      _callbacks.cancelCurrent();
      debugPrint('LevelPlay reward unavailable: $error');
      return null;
    } finally {
      _showing = false;
    }
  }

  void dispose() {
    _disposed = true;
    _callbacks.dispose();
    final ad = _ad;
    _ad = null;
    if (ad != null) unawaited(ad.dispose());
  }
}

class RewardAttempt {
  final loaded = Completer<bool>();
  final closed = Completer<bool>();
  String? auctionId;
}

/// One reusable native ad. Rewards belong to auction IDs, not the currently
/// open dialog: the SDK may deliver a reward after close or during a later load.
/// Only small deduplication IDs survive a completed impression; no per-view ad
/// objects, listeners or completed futures accumulate.
class RewardCallbacks implements LevelPlayRewardedAdListener {
  RewardCallbacks(this.onReward);
  final Future<void> Function() onReward;
  final _rewarded = <String>{};
  final _grants = <String, Future<void>>{};
  Future<void> _rewardQueue = Future<void>.value();
  RewardAttempt? _current;
  bool _disposed = false;

  RewardAttempt begin() {
    cancelCurrent();
    return _current = RewardAttempt();
  }

  void finish(RewardAttempt attempt, [bool rewarded = false]) {
    if (!attempt.loaded.isCompleted) attempt.loaded.complete(false);
    if (!attempt.closed.isCompleted) attempt.closed.complete(rewarded);
    if (identical(_current, attempt)) _current = null;
  }

  void cancelCurrent() {
    final attempt = _current;
    if (attempt != null) finish(attempt);
  }

  void dispose() {
    _disposed = true;
    cancelCurrent();
  }

  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) {
    final id = adInfo.auctionId;
    if (_disposed || id.isEmpty || !_rewarded.add(id)) return;
    // Serialize persistence so two late callbacks cannot race the entitlement.
    final grant = _rewardQueue.then((_) => onReward());
    _grants[id] = grant;
    _rewardQueue = grant.then(
      (_) {
        _grants.remove(id);
      },
      onError: (Object error, StackTrace stack) {
        _grants.remove(id);
        _rewarded.remove(id);
        debugPrint('Reward persistence failed: $error');
      },
    );
  }

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    final attempt = _current;
    if (attempt == null || attempt.auctionId != adInfo.auctionId) return;
    final grant = _grants[adInfo.auctionId];
    if (grant == null) {
      finish(attempt, _rewarded.contains(adInfo.auctionId));
    } else {
      unawaited(
        grant.then(
          (_) => finish(attempt, true),
          onError: (Object error, StackTrace stack) => finish(attempt),
        ),
      );
    }
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    final attempt = _current;
    if (attempt != null && !attempt.loaded.isCompleted) {
      attempt.loaded.complete(true);
    }
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    final attempt = _current;
    if (attempt != null && !attempt.loaded.isCompleted) {
      attempt.loaded.complete(false);
    }
  }

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    final attempt = _current;
    if (attempt != null &&
        (attempt.auctionId == null || attempt.auctionId == adInfo.auctionId)) {
      finish(attempt);
    }
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {
    _current?.auctionId = adInfo.auctionId;
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}
  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}
