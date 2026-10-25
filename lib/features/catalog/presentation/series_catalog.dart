import 'open_catalog_book.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reader_catalog.dart';
import 'book_catalog_row.dart';

class SeriesCover extends ConsumerWidget {
  const SeriesCover({super.key, required this.series, this.width = 56});
  final CatalogItem series;
  final double width;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(catalogCoverProvider(series)).valueOrNull;
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.auto_stories_outlined)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: width * 1.5,
        child: bytes == null
            ? fallback
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class SeriesCatalogRow extends StatelessWidget {
  const SeriesCatalogRow({
    super.key,
    required this.series,
    required this.onOpen,
  });
  final CatalogItem series;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('series-open-${series.id}'),
    onTap: onOpen,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          SeriesCover(series: series),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    series.author,
                    series.category,
                  ].where((value) => value.trim().isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  tr("{0} · {1}화 공개", [
                    tr(series.seriesStatusLabel),
                    series.episodeCount,
                  ]),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
    ),
  );
}

class ReaderSeriesPage extends ConsumerStatefulWidget {
  const ReaderSeriesPage({super.key, required this.series});
  final CatalogItem series;
  @override
  ConsumerState<ReaderSeriesPage> createState() => _ReaderSeriesPageState();
}

class _ReaderSeriesPageState extends ConsumerState<ReaderSeriesPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _newest = false;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    ReaderAnalytics.instance.seriesOpened(widget.series.id);
  }

  Future<void> _read(CatalogItem item) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openCatalogBook(context, ref, item);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String get _key => 'series:${widget.series.id}';
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _refresh() async {
    if (ref.read(catalogDownloadProvider).busy) return;
    ref.invalidate(catalogItemsProvider(_key));
    ref.invalidate(catalogInstalledProvider(_key));
    ref.invalidate(catalogItemsProvider('book'));
    try {
      await ref.read(catalogItemsProvider(_key).future);
    } catch (_) {
      /* Show retry. */
    }
  }

  Future<void> _download(CatalogItem item) async {
    try {
      await ref.read(catalogDownloadProvider.notifier).download(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr("{0}화를 내 서재에 추가했습니다.", [item.episodeNumber])),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is CatalogException
                  ? tr(error.message)
                  : tr("다운로드하지 못했습니다. 다시 시도해 주세요."),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogItemsProvider(_key));
    final installed = ref.watch(catalogInstalledProvider(_key));
    final download = ref.watch(catalogDownloadProvider);
    final parents = ref.watch(catalogItemsProvider('book')).valueOrNull;
    final series =
        parents?.where((item) => item.id == widget.series.id).firstOrNull ??
        widget.series;
    final reading = series.issueMonth.isNotEmpty
        ? ref.watch(libraryReadingStateProvider).valueOrNull
        : null;
    final today = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 9))
        .toIso8601String()
        .substring(0, 10);
    final query = _search.text.trim().toLowerCase();
    final episodes =
        (catalog.valueOrNull ?? const <CatalogItem>[])
            .where(
              (item) =>
                  item.seriesId == series.id &&
                  item.displayTitle.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) {
            final order = a.episodeNumber!.compareTo(b.episodeNumber!);
            return _newest ? -order : order;
          });
    return PopScope(
      canPop: !download.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr("다운로드가 끝날 때까지 잠시 기다려 주세요."))),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(series.title),
          actions: [
            IconButton(
              tooltip: tr("회차 목록 새로고침"),
              onPressed: download.busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                Flexible(
                  flex: 0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .55,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SeriesCover(series: series, width: 72),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      series.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      [series.author, series.category]
                                          .where(
                                            (value) => value.trim().isNotEmpty,
                                          )
                                          .join(' · '),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      tr("{0} · {1}화 공개", [
                                        tr(series.seriesStatusLabel),
                                        catalog.valueOrNull?.length ??
                                            series.episodeCount,
                                      ]),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (series.description.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(series.description),
                          ],
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(tr("출처·이용 조건")),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: SelectableText(
                                    [
                                      if (series.source.isNotEmpty)
                                        series.source,
                                      series.license,
                                    ].join('\n\n'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          TextField(
                            key: const ValueKey('series-episode-search'),
                            controller: _search,
                            onChanged: (_) => _changed(),
                            decoration: InputDecoration(
                              hintText: tr("회차 번호·제목 검색"),
                              prefixIcon: Icon(Icons.search),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text(tr("처음부터")),
                                selected: !_newest,
                                onSelected: (_) {
                                  _newest = false;
                                  _changed();
                                },
                              ),
                              ChoiceChip(
                                label: Text(tr("최신순")),
                                selected: _newest,
                                onSelected: (_) {
                                  _newest = true;
                                  _changed();
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      key: ValueKey('series-episodes-${series.id}'),
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: AdOverlayInsets.padding(
                        context,
                        const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      ),
                      itemCount: episodes.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            children: [
                              if (catalog.isLoading)
                                const LinearProgressIndicator(),
                              if (catalog.hasError || installed.hasError) ...[
                                const SizedBox(height: 16),
                                Text(
                                  catalog.error is CatalogException
                                      ? tr(
                                          (catalog.error as CatalogException)
                                              .message,
                                        )
                                      : tr("회차 목록이나 다운로드 상태를 확인하지 못했습니다."),
                                ),
                                TextButton(
                                  onPressed: download.busy ? null : _refresh,
                                  child: Text(tr("다시 시도")),
                                ),
                              ],
                              if (!catalog.isLoading &&
                                  !catalog.hasError &&
                                  episodes.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Text(
                                    query.isEmpty
                                        ? tr(
                                            "아직 공개된 회차가 없습니다.\n다음 화가 공개되면 이곳에서 내려받을 수 있습니다.",
                                          )
                                        : tr("검색 조건에 맞는 회차가 없습니다."),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          );
                        }
                        final episode = episodes[index - 1];
                        final key = catalogItemKey(episode);
                        final received =
                            installed.valueOrNull?.contains(key) ?? false;
                        return BookCatalogRow(
                          key: ValueKey(key),
                          item: episode,
                          installed: received,
                          onOpen:
                              series.issueMonth.isNotEmpty &&
                                  !download.busy &&
                                  !_opening
                              ? () => _read(episode)
                              : null,
                          isNew: episode.releaseDate == today,
                          readingLabel: series.issueMonth.isEmpty
                              ? null
                              : reading?[episode.bookId]?.finished == true
                              ? tr('완독')
                              : reading?[episode.bookId]?.progressLabel ??
                                    tr('아직 읽지 않은 이야기'),
                          progress: download.itemKey == key
                              ? download.progress
                              : null,
                          onDownload:
                              download.busy ||
                                  _opening ||
                                  installed.isLoading ||
                                  !installed.hasValue ||
                                  installed.hasError ||
                                  received
                              ? null
                              : () => _download(episode),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
