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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .55,
        minChildSize: .3,
        maxChildSize: .9,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: tr("닫기"),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(child: CatalogCover(item: item, width: 72)),
            const SizedBox(height: 12),
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(
              [
                item.author,
                tr(item.category),
              ].where((value) => value.trim().isNotEmpty).join(' · '),
            ),
            const SizedBox(height: 8),
            Text('${(item.totalSize / 1024 / 1024).toStringAsFixed(1)} MB'),
            if (isNew) const Text('NEW'),
            if (readingLabel != null) Text(readingLabel!),
            const SizedBox(height: 16),
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
                      ? '다운로드 완료'
                      : '다운로드',
                ),
              ),
            ),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(item.description),
            ],
            const SizedBox(height: 24),
            Text(
              tr("출처·이용 조건"),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (item.source.isNotEmpty) ...[
              SelectableText(item.source),
              const SizedBox(height: 8),
            ],
            SelectableText(item.license),
          ],
        ),
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
