import 'package:koofy_reader/features/catalog/presentation/editorial_story.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_cover.dart';
import 'package:koofy_reader/features/catalog/presentation/monthly_koofy_section.dart';
import 'package:koofy_reader/features/catalog/presentation/open_catalog_book.dart';
import 'package:koofy_reader/features/catalog/presentation/series_catalog.dart';
import 'package:koofy_reader/features/privacy/presentation/privacy_pages.dart';

/// The home is an editorial feed; books and reading history live in their tabs.
class DiscoveryFeed extends ConsumerStatefulWidget {
  const DiscoveryFeed({super.key});
  @override
  ConsumerState<DiscoveryFeed> createState() => _DiscoveryFeedState();
}

class _DiscoveryFeedState extends ConsumerState<DiscoveryFeed> {
  bool _opening = false;

  Future<void> _open(CatalogItem item) async {
    if (_opening || ref.read(catalogDownloadProvider).busy) return;
    setState(() => _opening = true);
    try {
      if (item.kind == 'series') {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderSeriesPage(series: item),
          ),
        );
      } else {
        await openCatalogBook(context, ref, item);
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(catalogItemsProvider('book'));
    final series = ref.watch(catalogItemsProvider('series'));
    final items = {
      for (final item in [...?books.valueOrNull, ...?series.valueOrNull])
        if (item.seriesId == null && item.issueMonth.isEmpty) item.id: item,
    }.values.toList()..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    final interviews = items
        .where((item) => item.category == '사람을 만나다')
        .toList();
    final newBooks = items
        .where((item) => item.category != '사람을 만나다')
        .take(6)
        .toList();
    final busy = _opening || ref.watch(catalogDownloadProvider).busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MonthlyKoofySection(editorial: true),
        const SizedBox(height: 24),
        const ReaderInvitationBanner(),
        const SizedBox(height: 36),
        Text(tr('새로 도착한 이야기'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 18),
        if (newBooks.isEmpty)
          Text(
            tr(
              books.isLoading || series.isLoading
                  ? '이야기를 불러오는 중입니다.'
                  : books.hasError || series.hasError
                  ? '이야기를 불러오지 못했습니다.'
                  : '새로운 이야기를 준비하고 있어요.',
            ),
          ),
        if (books.hasError || series.hasError)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                ref.invalidate(catalogItemsProvider('book'));
                ref.invalidate(catalogItemsProvider('series'));
              },
              child: Text(tr('다시 시도')),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final count = (constraints.maxWidth / (150 * scale)).floor().clamp(
              2,
              4,
            );
            final width = (constraints.maxWidth - (count - 1) * 18) / count;
            return Wrap(
              spacing: 18,
              runSpacing: 24,
              children: [
                for (final item in newBooks)
                  SizedBox(
                    width: width,
                    child: InkWell(
                      onTap: busy ? null : () => _open(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CatalogCover(item: item, width: width),
                          const SizedBox(height: 10),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (item.kind == 'series')
                            Text(
                              tr(item.seriesStatusLabel),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (interviews.isNotEmpty) ...[
          const SizedBox(height: 36),
          Text(tr('사람을 만나다'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          for (final item in interviews.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: EditorialStory(
                item: item,
                onTap: busy ? null : () => _open(item),
              ),
            ),
        ],
      ],
    );
  }
}

class ReaderInvitationBanner extends StatelessWidget {
  const ReaderInvitationBanner({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFE9EEDC),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          const ExcludeSemantics(
            child: Icon(
              Icons.mark_email_unread_outlined,
              size: 48,
              color: Color(0xFF61765C),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('독자 코너'),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('당신의 일상이, 누군가의 이야기가 됩니다.'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(tr('월간 쿠피에 당신의 글을 보내주세요.')),
                TextButton.icon(
                  onPressed: () => openReaderLink(
                    context,
                    Uri.https('www.koofy.co.kr', '/monthly-koofy/submit', {
                      'lang': AppLanguage.instance.code,
                    }),
                  ),
                  label: Text(tr('글 보내기')),
                  icon: const Icon(Icons.north_east, size: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
