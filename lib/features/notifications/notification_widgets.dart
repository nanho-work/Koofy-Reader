import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/open_catalog_book.dart';
import 'package:koofy_reader/features/catalog/presentation/series_catalog.dart';
import 'reader_notifications.dart';

class NotificationChoice extends StatefulWidget {
  const NotificationChoice({
    super.key,
    required this.base,
    required this.title,
  });
  final String base, title;
  @override
  State<NotificationChoice> createState() => _NotificationChoiceState();
}

class _NotificationChoiceState extends State<NotificationChoice> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: ReaderNotifications.instance,
    builder: (context, _) => SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(tr('새 글 알림 받기')),
      subtitle: Text(widget.title),
      value: ReaderNotifications.instance.subscriptions.containsKey(
        widget.base,
      ),
      onChanged: _busy
          ? null
          : (value) async {
              setState(() => _busy = true);
              try {
                await ReaderNotifications.instance.setSubscription(
                  widget.base,
                  widget.title,
                  value,
                );
              } catch (e) {
                if (context.mounted) {
                  ReaderAlerts.of(
                    context,
                  ).show(ReaderNotice(content: Text(localizedError(e))));
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    ),
  );
}

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('새 글 알림'))),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: ReaderNotifications.instance,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            NotificationChoice(base: 'monthly', title: tr('월간 쿠피')),
            NotificationChoice(base: 'books', title: tr('새로 출간된 책')),
            for (final e
                in ReaderNotifications.instance.subscriptions.entries.where(
                  (e) => e.key.startsWith('work_'),
                ))
              NotificationChoice(base: e.key, title: e.value),
            TextButton(
              onPressed: () async {
                try {
                  await ReaderNotifications.instance.sync();
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
    ),
  );
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
