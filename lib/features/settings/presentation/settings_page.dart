import 'dart:async';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'package:koofy_reader/features/ads/config/levelplay_ids.dart';
import 'package:koofy_reader/features/ads/data/levelplay_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/data/rewarded_ad_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _remaining(DateTime until) {
    final minutes = (until.difference(DateTime.now()).inSeconds / 60)
        .ceil()
        .clamp(1, 1000000);
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return hours == 0
        ? '$rest분 남음'
        : '$hours시간${rest == 0 ? '' : ' $rest분'} 남음';
  }

  @override
  Widget build(BuildContext context) {
    final adState = ref.watch(adStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('광고 없이 읽기', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('리워드 광고를 끝까지 시청하면 서재·설정·독서 화면의 배너가 2시간 동안 숨겨집니다.'),
          const SizedBox(height: 16),
          if (LevelPlayIds.testSuite)
            TextButton(
              onPressed: () async {
                if (await LevelPlayService.instance.initialize()) {
                  await LevelPlay.launchTestSuite();
                }
              },
              child: const Text('LevelPlay 광고 연동 테스트'),
            ),
          adState.when(
            loading: () => const Text('광고 상태를 불러오는 중입니다.'),
            error: (_, __) => TextButton(
              onPressed: () => ref.invalidate(adStateProvider),
              child: const Text('광고 상태를 불러오지 못했습니다. 다시 시도'),
            ),
            data: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.isBannerHidden
                      ? '광고 숨김 · ${_remaining(state.hiddenUntil!)}'
                      : '광고를 시청하고 2시간 동안 배너를 숨길 수 있습니다.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || state.isBannerHidden
                      ? null
                      : _runRewardedFlow,
                  child: Text(
                    _busy
                        ? '처리 중…'
                        : state.isBannerHidden
                        ? '광고 숨김 적용 중'
                        : '광고 보고 2시간 광고 없이 읽기',
                  ),
                ),
                if (state.isBannerHidden)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('숨김 시간이 끝나면 다시 시청할 수 있습니다.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runRewardedFlow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Check storage again to avoid starting another reward from stale UI.
      final state = await ref.read(adRepositoryProvider).getState();
      if (!mounted) return;
      if (state.isBannerHidden) {
        ref.invalidate(adStateProvider);
        return;
      }
      final result = await ref.read(rewardedAdServiceProvider).show();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == true
                ? '2시간 동안 배너 광고를 숨깁니다.'
                : result == false
                ? '광고가 닫혔습니다. 시청 보상이 확인되면 자동 적용됩니다.'
                : '광고를 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('광고 보상을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
