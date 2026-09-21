import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';

/// One font per row; its name opens details and the separate icon installs it.
class FontCatalogRow extends ConsumerWidget {
  const FontCatalogRow({
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
            Text(
              '${item.author} · ${(item.totalSize / 1024 / 1024).toStringAsFixed(1)} MB',
            ),
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
            const SizedBox(height: 24),
            const Text('내려받은 글꼴은 책의 독서 설정에서 선택할 수 있어요.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final preview = ref.watch(catalogFontPreviewProvider(item)).valueOrNull;
    final nameHeight = MediaQuery.textScalerOf(context).scale(22);
    final name = Text(
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                label: '${item.title}, 글꼴 정보',
                button: true,
                onTap: () => _details(context),
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => _details(context),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: preview == null
                              ? name
                              : SizedBox(
                                  height: nameHeight,
                                  width: double.infinity,
                                  child: Image.memory(
                                    preview,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                    color: colors.onSurface,
                                    colorBlendMode: BlendMode.srcIn,
                                    gaplessPlayback: true,
                                    errorBuilder: (_, _, _) => name,
                                  ),
                                ),
                        ),
                      ),
                    ),
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
                key: ValueKey('font-download-${item.id}'),
                tooltip: installed
                    ? '${item.title} 다운로드 완료'
                    : '${item.title} 다운로드',
                onPressed: onDownload,
                icon: Icon(installed ? Icons.check : Icons.download_outlined),
                color: colors.primary,
                disabledColor: installed ? colors.primary : null,
              ),
          ],
        ),
      ),
    );
  }
}
