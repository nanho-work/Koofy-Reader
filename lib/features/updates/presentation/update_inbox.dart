import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/core/widgets/reader_alert.dart';
import '../data/update_service.dart';
import '../domain/update_policy.dart';
import 'update_store_action.dart';

String _readKey(String version) => 'reader_update_inbox_read_v1_$version';

final _updateReadProvider = FutureProvider.family<bool, String>(
  (ref, version) async =>
      await ref.watch(localStorageProvider).getString(_readKey(version)) ==
      'read',
);

class UpdateInboxButton extends ConsumerWidget {
  const UpdateInboxButton({super.key});

  Future<void> _markRead(
    BuildContext context,
    WidgetRef ref,
    String version,
  ) async {
    try {
      await ref.read(localStorageProvider).setString(_readKey(version), 'read');
    } catch (_) {
      // Keep the dot if the read status could not be saved.
      return;
    }
    if (context.mounted) ref.invalidate(_updateReadProvider(version));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(updateNoticeProvider).valueOrNull;
    final optional = notice?.required == false ? notice : null;
    final read = optional == null
        ? null
        : ref.watch(_updateReadProvider(optional.latestVersion)).valueOrNull;

    final colors = Theme.of(context).colorScheme;
    final itemStyle = Theme.of(context).textTheme.bodyMedium;
    return PopupMenuButton<UpdateNotice>(
      tooltip: tr(read == false ? '알림함 · 읽지 않은 알림' : '알림함'),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant),
      ),
      icon: Badge(
        isLabelVisible: read == false,
        child: const Icon(Icons.notifications_none_rounded),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: optional,
          enabled: optional != null,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return itemStyle?.copyWith(color: colors.onSurfaceVariant);
            }
            return itemStyle;
          }),
          child: Text(
            optional == null
                ? tr('알림이 없어요')
                : tr('새 버전 {0}', [optional.latestVersion]),
          ),
        ),
      ],
      onSelected: (update) {
        if (read != true) {
          _markRead(context, ref, update.latestVersion);
        }
        showReaderDialog<void>(
          context: context,
          builder: (context) => ReaderAlertDialog(
            title: Text(tr('새 버전 {0}', [update.latestVersion])),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(update.message),
                const SizedBox(height: 16),
                UpdateStoreAction(url: update.storeUrl),
              ],
            ),
          ),
        );
      },
    );
  }
}
