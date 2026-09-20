import 'dart:async';
import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import '../config/levelplay_ids.dart';
import '../data/levelplay_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});
  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget>
    with WidgetsBindingObserver
    implements LevelPlayBannerAdViewListener {
  final _key = GlobalKey<LevelPlayBannerAdViewState>();
  bool _ready = false;
  bool _loaded = false;
  String _message = '광고 불러오는 중…';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    final ready = await LevelPlayService.instance.initialize();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      if (!ready) _message = '광고를 준비하지 못했습니다.';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_ready) {
        _initialize();
      } else {
        unawaited(_key.currentState?.resumeAutoRefresh());
      }
    } else {
      unawaited(_key.currentState?.pauseAutoRefresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The SDK platform view destroys its native banner when unmounted.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 320) return const SizedBox(height: 50);
      return SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 320,
            height: 50,
            child: Stack(
              children: [
                if (!_loaded)
                  Center(
                    child: Text(
                      _message,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (_ready)
                  LevelPlayBannerAdView(
                    key: _key,
                    adUnitId: LevelPlayIds.libraryBanner,
                    adSize: LevelPlayAdSize.BANNER,
                    listener: this,
                    onPlatformViewCreated: () {
                      unawaited(_key.currentState?.loadAd());
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    if (mounted) {
      setState(() {
        _loaded = false;
        _message = '광고를 불러오지 못했습니다.';
      });
    }
  }

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) =>
      onAdLoadFailed(error);
  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}
  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}
  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}
  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}
  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}
}
