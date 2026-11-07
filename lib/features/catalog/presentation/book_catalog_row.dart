import 'package:koofy_reader/features/notifications/notification_widgets.dart';
import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'catalog_cover.dart';
import 'catalog_shelf.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:flutter/material.dart';
import '../data/reader_catalog.dart';

/// A compact catalog entry; longer descriptions remain available on tap.
class BookCatalogRow extends StatelessWidget {
  const BookCatalogRow({
    super.key,
    required this.item,
    required this.installed,
    required this.progress,
    required this.onDownload,
    this.onOpen,
    this.readingLabel,
    this.isNew = false,
  });
  final CatalogItem item;
  final bool installed;
  final double? progress;
  final VoidCallback? onDownload, onOpen;
  final String? readingLabel;
  final bool isNew;

  void _details(BuildContext context) {
    showReaderDialog<void>(
      context: context,
      builder: (context) => ReaderAlertDialog(
        title: Text(item.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: CatalogCover(item: item, width: 72)),
            if (item.seriesId == null)
              FavoriteButton(item: item, showLabel: true),
            const SizedBox(height: 16),
            Text(
              [
                item.author,
                tr(item.category),
              ].where((v) => v.trim().isNotEmpty).join(' · '),
            ),
            const SizedBox(height: 8),
            Text('${(item.totalSize / 1024 / 1024).toStringAsFixed(1)} MB'),
            if (isNew) const Text('NEW'),
            if (readingLabel != null) Text(readingLabel!),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(item.description),
            ],
            const SizedBox(height: 20),
            Text(tr('출처·이용 조건'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (item.source.isNotEmpty) ...[
              SelectableText(item.source),
              const SizedBox(height: 8),
            ],
            SelectableText(item.license),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('닫기')),
          ),
          FilledButton.icon(
            key: ValueKey('book-download-${item.id}'),
            onPressed: (onOpen ?? onDownload) == null
                ? null
                : () {
                    Navigator.pop(context);
                    (onOpen ?? onDownload)?.call();
                  },
            icon: Icon(
              onOpen != null
                  ? Icons.menu_book_outlined
                  : installed
                  ? Icons.check
                  : Icons.download_outlined,
            ),
            label: Text(
              tr(
                onOpen != null
                    ? '읽기'
                    : installed
                    ? '서재에 있음'
                    : '다운로드',
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CatalogShelfCard(
    item: item,
    installed: installed,
    progress: progress,
    onTap: () => _details(context),
  );
}
