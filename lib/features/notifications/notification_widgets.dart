import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/open_catalog_book.dart';
import 'package:koofy_reader/features/catalog/presentation/series_catalog.dart';
import 'reader_notifications.dart';

/// The same star is used by catalog covers and work details.
class FavoriteButton extends ConsumerStatefulWidget {
  const FavoriteButton({super.key, required this.item, this.showLabel = false});
  final CatalogItem item;
  final bool showLabel;
  @override
  ConsumerState<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<FavoriteButton> {
  bool _busy = false;
  Future<void> _toggle() async {
    final service = ref.read(readerNotificationsProvider);
    setState(() => _busy = true);
    try {
      await service.initialize();
      await service.reconcile([widget.item]);
      final next = !service.isFavorite(widget.item);
      await service.setFavorite(
        notificationBase(widget.item),
        widget.item.title,
        next,
      );
      if (next && mounted && await service.claimFavoriteNotice() && mounted) {
        final enable = await showReaderDialog<bool>(
          context: context,
          builder: (context) => ReaderAlertDialog(
            title: Text(tr('새 이야기 알림')),
            content: Text(tr('즐겨찾기한 책에 새로운 이야기가 올라오면 알려드려요. 알림을 켤까요?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('나중에')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(tr('알림 켜기')),
              ),
            ],
          ),
        );
        if (enable == true) {
          if (service.asked && !service.allowed) {
            await service.openSettings();
          } else {
            await service.enableNotifications();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ReaderAlerts.of(
          context,
        ).show(ReaderNotice(content: Text(localizedError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationPreferencesProvider);
    ref.watch(readerNotificationsChangesProvider);
    final service = ref.watch(readerNotificationsProvider);
    final selected = service.isFavorite(widget.item);
    final label = tr(selected ? '즐겨찾기 해제' : '즐겨찾기 추가');
    final icon = Icon(
      selected ? Icons.star_rounded : Icons.star_outline_rounded,
    );
    if (widget.showLabel) {
      return TextButton.icon(
        key: ValueKey('favorite-detail-${widget.item.id}'),
        onPressed: _busy ? null : _toggle,
        icon: icon,
        label: Text(label),
      );
    }
    return IconButton(
      key: ValueKey('favorite-${widget.item.id}'),
      tooltip: label,
      isSelected: selected,
      onPressed: _busy ? null : _toggle,
      icon: icon,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: .95),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationPreferencesProvider);
    ref.watch(readerNotificationsChangesProvider);
    final service = ref.watch(readerNotificationsProvider);
    Future<void> change(bool value) async {
      try {
        if (!value) {
          await service.disableNotifications();
        } else if (service.asked && !service.allowed) {
          await service.openSettings();
        } else {
          await service.enableNotifications();
        }
      } catch (e) {
        if (context.mounted) {
          ReaderAlerts.of(
            context,
          ).show(ReaderNotice(content: Text(localizedError(e))));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr('새 글 알림'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('즐겨찾기 새 글 알림')),
              subtitle: Text(
                tr('별표한 작품의 새 회차와 월간 쿠피 소식을 받아요. 즐겨찾기는 도서에서 관리할 수 있어요.'),
              ),
              value: service.enabled && service.allowed,
              onChanged: service.available ? change : null,
            ),
            if (!service.allowed)
              Text(
                tr('기기에서 알림이 허용되어야 새 글 알림을 받을 수 있어요. 즐겨찾기는 알림 없이도 사용할 수 있어요.'),
              ),
            if (service.legacyBooks)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('기존 전체 새 글 알림')),
                value: true,
                subtitle: Text(
                  tr('이전에 선택한 전체 새 글 알림입니다. 끄면 즐겨찾기한 작품의 소식만 받아요.'),
                ),
                onChanged: (_) async {
                  try {
                    await service.disableLegacyBooks();
                  } catch (e) {
                    if (context.mounted) {
                      ReaderAlerts.of(
                        context,
                      ).show(ReaderNotice(content: Text(localizedError(e))));
                    }
                  }
                },
              ),
            if (service.connectionError != null) Text(service.connectionError!),
            TextButton(
              onPressed: () async {
                try {
                  await service.sync();
                } catch (e) {
                  if (context.mounted) {
                    ReaderAlerts.of(
                      context,
                    ).show(ReaderNotice(content: Text(localizedError(e))));
                  }
                }
              },
              child: Text(tr('알림 연결 다시 확인')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Consumes notification taps after the normal application gates are mounted.
class NotificationEntry extends ConsumerStatefulWidget {
  const NotificationEntry({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<NotificationEntry> createState() => _NotificationEntryState();
}

class _NotificationEntryState extends ConsumerState<NotificationEntry> {
  StreamSubscription<Map<String, String>>? _subscription;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _subscription = ReaderNotifications.instance.opens.stream.listen(_open);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = ReaderNotifications.instance.pending;
      if (data != null) _open(data);
    });
  }

  Future<void> _open(Map<String, String> data) async {
    if (_opening || !mounted) return;
    _opening = true;
    ReaderNotifications.instance.pending = null;
    try {
      final catalog = ref.read(readerCatalogProvider);
      final parent = data['seriesId'];
      final key = parent != null && parent.isNotEmpty
          ? 'series:$parent'
          : 'book';
      catalog.forceRefresh(key);
      final items = await catalog.completeItems(key);
      final item = items
          .where((i) => i.id == data['id'] && !i.upcoming)
          .firstOrNull;
      if (!mounted) return;
      if (item == null) throw StateError(tr('현재 공개된 글을 찾을 수 없습니다.'));
      if (item.kind == 'series') {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderSeriesPage(series: item),
          ),
        );
      } else {
        await openCatalogBook(context, ref, item);
      }
    } catch (e) {
      if (mounted) {
        ReaderAlerts.of(
          context,
        ).show(ReaderNotice(content: Text(localizedError(e))));
      }
    } finally {
      _opening = false;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
