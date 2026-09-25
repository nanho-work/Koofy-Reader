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
  });
  final CatalogItem item;
  final bool installed;
  final double? progress;
  final VoidCallback? onDownload;

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
                tooltip: '닫기',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text('${item.author} · ${item.category}'),
            const SizedBox(height: 8),
            Text('${(item.totalSize / 1024 / 1024).toStringAsFixed(1)} MB'),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(item.description),
            ],
            const SizedBox(height: 24),
            Text('출처·이용 조건', style: Theme.of(context).textTheme.titleMedium),
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
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.author} · ${item.category}',
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
                    semanticsLabel: '${item.title} 다운로드 중',
                    semanticsValue: '${(progress! * 100).round()}%',
                  ),
                ),
              ),
            )
          else
            IconButton(
              key: ValueKey('book-download-${item.id}'),
              tooltip: '${item.title} ${installed ? '다운로드 완료' : '다운로드'}',
              onPressed: onDownload,
              icon: Icon(installed ? Icons.check : Icons.download_outlined),
              color: colors.primary,
              disabledColor: installed ? colors.primary : null,
            ),
        ],
      ),
    );
  }
}
