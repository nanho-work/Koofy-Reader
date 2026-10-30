import 'package:koofy_reader/core/widgets/selection_menu.dart';
import 'catalog_cover.dart';
import 'catalog_shelf.dart';
import 'open_catalog_book.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reader_catalog.dart';
import 'book_catalog_row.dart';

class SeriesCatalogRow extends StatelessWidget {
  const SeriesCatalogRow({
    super.key,
    required this.series,
    required this.onOpen,
  });
  final CatalogItem series;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => CatalogShelfCard(
    key: ValueKey('series-open-${series.id}'),
    item: series,
    onTap: onOpen,
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
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = usesReaderSidebar(constraints.maxWidth);
              final info = _SeriesInformation(
                series: series,
                expanded: wide,
                count: catalog.valueOrNull?.length ?? series.episodeCount,
              );
              final back = Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('series-back-to-books'),
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    minimumSize: const Size(48, 48),
                  ),
                  icon: const Icon(Icons.chevron_left, size: 24),
                  label: Text(tr('도서')),
                ),
              );
              final controls = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      children: [
                        SelectionMenuChip(
                          label: tr("처음부터"),
                          selected: !_newest,
                          onSelected: (_) {
                            _newest = false;
                            _changed();
                          },
                        ),
                        SelectionMenuChip(
                          label: tr("최신순"),
                          selected: _newest,
                          onSelected: (_) {
                            _newest = true;
                            _changed();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('series-episode-search'),
                      controller: _search,
                      onChanged: (_) => _changed(),
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: tr('회차 번호·제목 검색'),
                        prefixIcon: const Icon(Icons.search),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('회차 목록 새로고침'),
                    onPressed: download.busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              );
              final list = RefreshIndicator(
                onRefresh: _refresh,
                child: CatalogShelfList(
                  key: ValueKey('series-episodes-${series.id}'),
                  controller: _scroll,
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
                              padding: const EdgeInsets.symmetric(vertical: 24),
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
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: (constraints.maxWidth * .30).clamp(200.0, 300.0),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8, top: 8),
                            child: back,
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const PageStorageKey(
                                'series-information-wide',
                              ),
                              primary: false,
                              padding: const EdgeInsets.all(16),
                              child: info,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          Flexible(
                            flex: 0,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight * .45,
                              ),
                              child: SingleChildScrollView(
                                primary: false,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  12,
                                ),
                                child: controls,
                              ),
                            ),
                          ),
                          Expanded(child: list),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  Padding(padding: const EdgeInsets.only(left: 8), child: back),
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .55,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Column(children: [info, controls]),
                      ),
                    ),
                  ),
                  Expanded(child: list),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SeriesInformation extends StatelessWidget {
  const _SeriesInformation({
    required this.series,
    required this.count,
    required this.expanded,
  });
  final CatalogItem series;
  final int count;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(series.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        if (series.author.trim().isNotEmpty) Text(series.author),
        const SizedBox(height: 6),
        Text(tr('{0} · {1}화 공개', [tr(series.seriesStatusLabel), count])),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expanded) ...[
          Center(child: CatalogCover(item: series, width: 140)),
          const SizedBox(height: 16),
          summary,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CatalogCover(item: series, width: 72),
              const SizedBox(width: 16),
              Expanded(child: summary),
            ],
          ),
        if (series.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(series.description),
        ],
        ExpansionTile(
          key: PageStorageKey('series-source-license-${series.id}'),
          tilePadding: EdgeInsets.zero,
          title: Text(tr('출처·이용 조건')),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SelectableText(
                  // Isolate the text's numeric scroll offset from the tile's boolean expansion state.
                  key: PageStorageKey('series-license-text-${series.id}'),
                  [
                    if (series.source.isNotEmpty) series.source,
                    series.license,
                  ].join('\n\n'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
