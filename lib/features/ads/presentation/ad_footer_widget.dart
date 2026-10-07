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
  const AdFooterWidget({super.key, this.showStatusMessages = true});

  final bool showStatusMessages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adStateAsync = ref.watch(adStateProvider);
    final connectivityAsync = ref.watch(connectivityResultsProvider);

    Widget unavailable(String message) =>
        showStatusMessages ? _AdBox(message: message) : const SizedBox.shrink();
    return adStateAsync.when(
      loading: () => const SizedBox(height: 50),
      error: (_, _) => unavailable('지금은 광고를 표시할 수 없습니다.'),
      data: (adState) {
        if (adState.isBannerHidden) {
          return const SizedBox.shrink();
        }
        return connectivityAsync.when(
          loading: () => const SizedBox(height: 50),
          error: (_, _) => unavailable('지금은 광고를 표시할 수 없습니다.'),
          data: (results) {
            final connected = results.any((e) => e != ConnectivityResult.none);
            if (connected) {
              return BannerAdWidget(showStatusMessages: showStatusMessages);
            }
            return unavailable('오프라인에서도 독서를 계속할 수 있습니다.');
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
