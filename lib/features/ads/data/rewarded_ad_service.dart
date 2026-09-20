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
  RewardedAdService({Future<void> Function()? onReward})
    : _onReward = onReward ?? _noop;
  static Future<void> _noop() async {}
  final Future<void> Function() _onReward;
  final List<RewardAttempt> _attempts = [];
  bool _showing = false;
  bool _disposed = false;

  Future<bool?> show() async {
    if (_showing || _disposed) return null;
    _showing = true;
    _attempts.removeWhere((attempt) => attempt.isDisposed);
    RewardAttempt? pending;
    try {
      if (!await LevelPlayService.instance.initialize() || _disposed) {
        return null;
      }
      final ad = LevelPlayRewardedAd(adUnitId: LevelPlayIds.rewarded);
      final attempt = RewardAttempt(ad: ad, onReward: _onReward);
      pending = attempt;
      _attempts.add(attempt);
      ad.setListener(attempt);
      await ad.loadAd();
      if (!await attempt.loaded.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      )) {
        await attempt.dispose();
        _attempts.remove(attempt);
        return null;
      }
      if (_disposed || !await ad.isAdReady()) {
        await attempt.dispose();
        return null;
      }
      await ad.showAd();
      // Closing settles the UI only. The attempt remains registered so that a
      // reward arriving AFTER close still persists, even off the settings page.
      return await attempt.closed.future;
    } catch (error) {
      if (pending != null) await pending.dispose();
      debugPrint('LevelPlay reward unavailable: $error');
      return null;
    } finally {
      _showing = false;
    }
  }

  void dispose() {
    _disposed = true;
    for (final attempt in _attempts) {
      unawaited(attempt.dispose());
    }
    _attempts.clear();
  }
}

/// One listener per ad object associates delayed/duplicate callbacks with the
/// correct viewing; a later viewing cannot consume the earlier one's reward.
class RewardAttempt implements LevelPlayRewardedAdListener {
  RewardAttempt({required this.ad, required this.onReward});
  final LevelPlayRewardedAd ad;
  final Future<void> Function() onReward;
  final loaded = Completer<bool>();
  final closed = Completer<bool>();
  Future<void>? _grant;
  bool _disposed = false;
  bool _isClosed = false;
  bool get isDisposed => _disposed;
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!loaded.isCompleted) loaded.complete(false);
    if (!closed.isCompleted) closed.complete(false);
    await ad.dispose();
  }

  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) {
    if (_disposed || _grant != null) return;
    _grant = onReward();
    unawaited(
      _grant!
          .then((_) async {
            if (_isClosed) {
              if (!closed.isCompleted) closed.complete(true);
              await dispose();
            }
          })
          .catchError((Object error) {
            debugPrint('Reward persistence failed: $error');
          }),
    );
  }

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    _isClosed = true;
    final grant = _grant;
    if (grant == null) {
      if (!closed.isCompleted) closed.complete(false);
    } else {
      unawaited(
        grant
            .then((_) async {
              if (!closed.isCompleted) closed.complete(true);
              await dispose();
            })
            .catchError((Object error) {
              if (!closed.isCompleted) closed.completeError(error);
            }),
      );
    }
  }

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    if (!loaded.isCompleted) loaded.complete(true);
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    if (!loaded.isCompleted) loaded.complete(false);
  }

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    if (!closed.isCompleted) closed.complete(false);
    unawaited(dispose());
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}
  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}
  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}
