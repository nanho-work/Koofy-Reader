import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/presentation/banner_ad_widget.dart';

final connectivityResultsProvider = StreamProvider<List<ConnectivityResult>>((
  ref,
) {
  return Connectivity().onConnectivityChanged;
});

class AdFooterWidget extends ConsumerWidget {
  const AdFooterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adStateAsync = ref.watch(adStateProvider);
    final connectivityAsync = ref.watch(connectivityResultsProvider);

    return adStateAsync.when(
      loading: () => _AdBox(message: '광고 상태 확인중...'),
      error: (_, _) => _AdBox(message: '광고 정보를 불러오지 못했습니다.'),
      data: (adState) {
        if (adState.isBannerHidden) {
          return _AdBox(message: '광고 숨김 적용 중');
        }
        return connectivityAsync.when(
          loading: () => _AdBox(message: '광고 로딩중...'),
          error: (_, _) => _AdBox(message: '네트워크 상태 확인 실패'),
          data: (results) {
            final connected = results.any((e) => e != ConnectivityResult.none);
            if (connected) {
              return const BannerAdWidget();
            }
            return _AdBox(message: '네트워크 연결 필요');
          },
        );
      },
    );
  }
}

class _AdBox extends StatelessWidget {
  const _AdBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
