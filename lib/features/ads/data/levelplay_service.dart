import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import '../config/levelplay_ids.dart';

final levelPlayReadyProvider = FutureProvider<bool>(
  (ref) => LevelPlayService.instance.initialize(),
);

class LevelPlayService implements LevelPlayInitListener {
  static final instance = LevelPlayService();
  Completer<bool>? _initializing;
  bool _ready = false;
  Future<bool> initialize() async {
    if (!LevelPlayIds.supported) return false;
    if (_ready) return true;
    if (_initializing != null) {
      return _initializing!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    }
    final attempt = Completer<bool>();
    _initializing = attempt;
    try {
      if (LevelPlayIds.testSuite) {
        await LevelPlay.setMetaData({
          'is_test_suite': ['enable'],
        });
      }
      await LevelPlay.init(
        initRequest: LevelPlayInitRequest.builder(LevelPlayIds.appKey).build(),
        initListener: this,
      );
    } catch (error) {
      debugPrint('LevelPlay initialization unavailable: $error');
      if (!attempt.isCompleted) attempt.complete(false);
      _initializing = null;
    }
    return attempt.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => false,
    );
  }

  @override
  void onInitSuccess(LevelPlayConfiguration configuration) {
    _ready = true;
    if (_initializing?.isCompleted == false) _initializing!.complete(true);
    _initializing = null;
  }

  @override
  void onInitFailed(LevelPlayInitError error) {
    debugPrint('LevelPlay initialization failed: $error');
    if (_initializing?.isCompleted == false) _initializing!.complete(false);
    _initializing = null;
  }
}
