import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/presentation/banner_ad_widget.dart';

class AdFooterWidget extends ConsumerWidget {
  const AdFooterWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adStateAsync = ref.watch(adStateProvider);

    return adStateAsync.when(
      loading: () => _AdBox(
        message: '광고 상태 확인중...',
        backgroundColor: Colors.grey.shade100,
      ),
      error: (_, _) => _AdBox(
        message: '광고 정보를 불러오지 못했습니다.',
        backgroundColor: Colors.red.shade50,
      ),
      data: (adState) {
        if (adState.isBannerHidden) {
          return _AdBox(
            message: '보상 적용중: 상단 광고 숨김',
            backgroundColor: Colors.green.shade50,
          );
        }
        return StreamBuilder<List<ConnectivityResult>>(
          stream: Connectivity().onConnectivityChanged,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _AdBox(
                message: '광고 로딩중...',
                backgroundColor: Colors.blue.shade50,
              );
            }
            final connected =
                snapshot.data?.any((e) => e != ConnectivityResult.none) ??
                false;
            if (connected) {
              return const BannerAdWidget();
            }
            return _AdBox(
              message: '네트워크 연결 필요',
              backgroundColor: Colors.grey.shade100,
            );
          },
        );
      },
    );
  }
}

class _AdBox extends StatelessWidget {
  const _AdBox({required this.message, required this.backgroundColor});

  final String message;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
