import 'package:intl/intl.dart' show DateFormat;
import 'package:koofy_reader/core/widgets/book_shelf_layout.dart';
export 'package:koofy_reader/core/widgets/book_shelf_layout.dart';
import 'package:flutter/material.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import '../data/reader_catalog.dart';
import 'catalog_cover.dart';

/// Shared cover/title treatment for works and individual episodes.
class CatalogShelfCard extends StatelessWidget {
  const CatalogShelfCard({
    super.key,
    required this.item,
    required this.onTap,
    this.progress,
    this.installed = false,
  });
  final CatalogItem item;
  final VoidCallback? onTap;
  final double? progress;
  final bool installed;

  static double titleHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) * 1.4 * 2;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = item.episodeNumber != null && item.episodeTitle != null
        ? tr('{0}화 · {1}', [item.episodeNumber, item.episodeTitle])
        : item.title;
    return Semantics(
      button: !item.upcoming,
      label: [
        title,
        if (item.kind == 'series') tr(item.seriesStatusLabel),
        if (installed) tr('다운로드 완료'),
        if (item.upcoming) _releaseLabel(item),
      ].join(', '),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: item.upcoming ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: .10),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Opacity(
                      opacity: item.upcoming ? .38 : 1,
                      child: CatalogCover(
                        item: item,
                        width: constraints.maxWidth,
                      ),
                    ),
                  ),
                  if (item.kind == 'series')
                    Positioned(
                      top: 6,
                      left: 6,
                      right: 6,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: .95),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tr(item.seriesStatusLabel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (installed && progress == null)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: .96),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 13,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                tr('서재에 있음'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (progress != null)
                    Positioned.fill(
                      child: ColoredBox(
                        color: colors.surface.withValues(alpha: .65),
                        child: Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 2,
                              semanticsLabel: tr('{0} 다운로드 중', [title]),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: titleHeight(context),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (item.upcoming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _releaseLabel(item),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    height: 1.4,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Index zero is a full-width loading/error/empty header; other items are lazy.
class CatalogShelfList extends StatelessWidget {
  const CatalogShelfList({
    super.key,
    required this.controller,
    required this.padding,
    required this.itemCount,
    required this.itemBuilder,
    this.grid = true,
  });
  final ScrollController controller;
  final EdgeInsets padding;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    if (!grid) {
      return ListView.builder(
        controller: controller,
        padding: padding,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final columns = catalogShelfColumns(
          window: MediaQuery.sizeOf(context),
          shelfWidth: width,
          textScale: scale,
        );
        final tileWidth = (width - (columns - 1) * bookShelfSpacing) / columns;
        return CustomScrollView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                padding.top,
                padding.right,
                0,
              ),
              sliver: SliverToBoxAdapter(child: itemBuilder(context, 0)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                8,
                padding.right,
                padding.bottom,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: bookShelfSpacing,
                  mainAxisSpacing: 22,
                  mainAxisExtent:
                      tileWidth * 1.5 +
                      8 +
                      CatalogShelfCard.titleHeight(context) +
                      8 +
                      MediaQuery.textScalerOf(context).scale(11) * 1.4 * 2,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => itemBuilder(context, index + 1),
                  childCount: itemCount - 1,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _releaseLabel(CatalogItem item) {
  final date = DateTime.tryParse(
    item.releaseAt.isNotEmpty
        ? item.releaseAt
        : '${item.releaseDate}T00:00:00+09:00',
  );
  return date == null
      ? tr('공개 예정')
      : tr('{0} 공개 예정', [
          DateFormat.Md(
            AppLanguage.instance.code,
          ).add_Hm().format(date.toLocal()),
        ]);
}
