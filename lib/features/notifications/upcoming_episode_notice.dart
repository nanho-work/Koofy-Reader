import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'notification_widgets.dart';
import 'reader_notifications.dart';

/// Resolve the work before saving a star: an episode ID must never become a
/// work subscription. Monthly favorites retain the existing whole-corner key.
Future<void> showUpcomingEpisodeNotice(
  BuildContext context,
  CatalogItem episode, {
  required String message,
}) => showReaderDialog<void>(
  context: context,
  builder: (dialogContext) => ReaderAlertDialog(
    title: Text(tr('공개 예정')),
    content: _UpcomingFavoriteContent(episode: episode, message: message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: Text(tr('닫기')),
      ),
    ],
  ),
);

class _UpcomingFavoriteContent extends ConsumerStatefulWidget {
  const _UpcomingFavoriteContent({
    required this.episode,
    required this.message,
  });
  final CatalogItem episode;
  final String message;
  @override
  ConsumerState<_UpcomingFavoriteContent> createState() =>
      _UpcomingFavoriteContentState();
}

class _UpcomingFavoriteContentState
    extends ConsumerState<_UpcomingFavoriteContent> {
  late Future<CatalogItem?> _work;
  bool _enabling = false;
  Future<CatalogItem?> _load() async {
    final works = await ref
        .read(readerCatalogProvider)
        .completeItems(
          'book',
          language: widget.episode.json['language'] as String?,
        );
    return works
        .where(
          (work) => work.kind == 'series' && work.id == widget.episode.seriesId,
        )
        .firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _work = _load();
  }

  Future<void> _enable() async {
    setState(() => _enabling = true);
    try {
      await enableReaderStoryNotifications(
        ref.read(readerNotificationsProvider),
      );
    } catch (error) {
      if (mounted) {
        ReaderAlerts.of(
          context,
        ).show(ReaderNotice(content: Text(localizedError(error))));
      }
    } finally {
      if (mounted) setState(() => _enabling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationPreferencesProvider);
    ref.watch(readerNotificationsChangesProvider);
    final service = ref.watch(readerNotificationsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.message),
        const SizedBox(height: 12),
        Text(tr('작품을 즐겨찾기하면 새 회차 알림을 받을 수 있어요. 알림은 설정에서 켤 수 있어요.')),
        const SizedBox(height: 8),
        FutureBuilder<CatalogItem?>(
          future: _work,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LinearProgressIndicator();
            }
            final work = snapshot.data;
            if (work == null) {
              return TextButton(
                onPressed: () => setState(() => _work = _load()),
                child: Text(tr('작품 정보 다시 확인')),
              );
            }
            final selected = service.isFavorite(work);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FavoriteButton(item: work, showLabel: true, addOnly: true),
                if (selected &&
                    service.available &&
                    (!service.allowed || !service.enabled))
                  TextButton(
                    onPressed: _enabling ? null : _enable,
                    child: Text(tr('새 글 알림 받기')),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
