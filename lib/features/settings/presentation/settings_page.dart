import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/data/rewarded_ad_service.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adStateAsync = ref.watch(adStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('광고 설정', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          adStateAsync.when(
            loading: () => const Text('광고 상태를 불러오는 중입니다.'),
            error: (error, _) => Text('광고 상태 로드 실패: $error'),
            data: (state) {
              final hiddenUntil = state.hiddenUntil;
              final hiddenText = hiddenUntil == null
                  ? '비활성'
                  : DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(hiddenUntil.toLocal());
              return Text('상단 광고 숨김 만료: $hiddenText');
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => _runRewardedFlow(context, ref, 5),
                child: const Text('보상형 5시간'),
              ),
              FilledButton.tonal(
                onPressed: () => _runRewardedFlow(context, ref, 6),
                child: const Text('보상형 6시간'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '오프라인 안내\n네트워크가 없으면 광고 영역에 안내 문구만 표시됩니다.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Future<void> _runRewardedFlow(
    BuildContext context,
    WidgetRef ref,
    int hours,
  ) async {
    final result = await ref.read(rewardedAdServiceProvider).show();
    if (result == true) {
      await ref.read(adRepositoryProvider).hideBannerForHours(hours);
      ref.invalidate(adStateProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('보상 적용 완료: $hours시간')));
      return;
    }

    if (!context.mounted) return;
    final message = result == false
        ? '보상을 받지 못했습니다. 다시 시도해 주세요.'
        : '리워드 광고 준비중입니다. 잠시 후 다시 시도해 주세요.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
