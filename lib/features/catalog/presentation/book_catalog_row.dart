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
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('${item.author} · ${tr(item.category)}'),
            const SizedBox(height: 8),
            Text('${(item.totalSize / 1024 / 1024).toStringAsFixed(1)} MB'),
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _details(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isNew)
                      Text(
                        tr('새 이야기'),
                        style: TextStyle(color: colors.primary),
                      ),
                    Text(
                      item.seriesId == null
                          ? item.title
                          : tr('{0}화 · {1}', [
                              item.episodeNumber,
                              item.episodeTitle,
                            ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    if (readingLabel != null)
                      Text(
                        readingLabel!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    Text(
                      '${item.author} · ${tr(item.category)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (progress != null)
            SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 2,
                    semanticsLabel: tr("{0} 다운로드 중", [item.title]),
                    semanticsValue: '${(progress! * 100).round()}%',
                  ),
                ),
              ),
            )
          else
            IconButton(
              key: ValueKey('book-download-${item.id}'),
              tooltip:
                  '${item.title} ${tr(onOpen != null
                      ? '읽기'
                      : installed
                      ? '다운로드 완료'
                      : '다운로드')}',
              onPressed: onOpen ?? onDownload,
              icon: Icon(
                onOpen != null
                    ? Icons.menu_book_outlined
                    : installed
                    ? Icons.check
                    : Icons.download_outlined,
              ),
              color: colors.primary,
              disabledColor: installed ? colors.primary : null,
            ),
        ],
      ),
    );
  }
}
