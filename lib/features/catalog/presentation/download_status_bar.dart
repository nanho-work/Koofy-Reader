import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import '../data/reader_catalog.dart';

class DownloadStatusBar extends ConsumerWidget {
  const DownloadStatusBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(catalogDownloadProvider);
    if (!state.busy) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: state.progress, minHeight: 2),
          Row(
            children: [
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  '${state.title} · ${(state.progress * 100).round()}%${state.queued > 0 ? ' · ${tr('대기 {0}권', [state.queued])}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(catalogDownloadProvider.notifier).cancel(),
                child: Text(tr('취소')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
