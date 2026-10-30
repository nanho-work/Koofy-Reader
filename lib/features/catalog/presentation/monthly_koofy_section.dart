import 'promotion_carousel.dart';
import 'editorial_story.dart';
import 'catalog_cover.dart';
import 'dart:async';
import 'package:koofy_reader/features/privacy/presentation/privacy_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import '../data/reader_catalog.dart';
import 'series_catalog.dart';
import 'open_catalog_book.dart';

/// Daily entry points share the catalog book identity and native reading records.
class MonthlyKoofySection extends ConsumerStatefulWidget {
  const MonthlyKoofySection({
    super.key,
    this.editorial = false,
    this.promotions = const [],
  });
  final List<Widget> promotions;
  final bool editorial;
  @override
  ConsumerState<MonthlyKoofySection> createState() =>
      _MonthlyKoofySectionState();
}

class _MonthlyKoofySectionState extends ConsumerState<MonthlyKoofySection>
    with WidgetsBindingObserver {
  Timer? _timer;
  Set<String> _dismissed = {};
  bool _preferencesLoaded = false;
  bool _opening = false;
  bool _expanded = true;
  bool _savingExpansion = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _dismissed =
              (prefs.getStringList('monthly_compilations_dismissed_v1') ?? [])
                  .toSet();
          _expanded = prefs.getBool('monthly_section_expanded_v1') ?? true;
          _preferencesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _preferencesLoaded = true);
    }
  }

  void _refresh() {
    if (!mounted || ref.read(catalogDownloadProvider).busy || _opening) return;
    ref.invalidate(monthlyGroupCoverSyncProvider);
    ref.invalidate(catalogItemsProvider('monthly'));
    ref.invalidate(catalogItemsProvider('book'));
    ref.invalidate(catalogItemsProvider('series'));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _dismiss(CatalogItem item) async {
    final next = {..._dismissed, item.id};
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(
        'monthly_compilations_dismissed_v1',
        next.toList(),
      )) {
        throw StateError('save');
      }
      if (mounted) setState(() => _dismissed = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('저장하지 못했습니다. 다시 시도해 주세요.'))));
      }
    }
  }

  Future<void> _toggleExpanded() async {
    if (_savingExpansion || !_preferencesLoaded) return;
    final next = !_expanded;
    setState(() {
      _expanded = next;
      _savingExpansion = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool('monthly_section_expanded_v1', next)) {
        throw StateError('save');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _expanded = !next);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('저장하지 못했습니다. 다시 시도해 주세요.'))));
      }
    } finally {
      if (mounted) setState(() => _savingExpansion = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(catalogItemsProvider('monthly'));
    // Existing offline reading must remain available when the feed cannot load.
    final items = result.valueOrNull ?? const <CatalogItem>[];
    final issues = items.where((item) => item.kind == 'series').toList()
      ..sort((a, b) => b.issueMonth.compareTo(a.issueMonth));
    final issue = issues.firstOrNull;
    final episode = items
        .where((item) => item.seriesId == issue?.id && item.seriesId != null)
        .firstOrNull;
    final compilations = items.where(
      (item) =>
          item.kind == 'book' &&
          item.seriesId == null &&
          !_dismissed.contains(item.id),
    );
    final download = ref.watch(catalogDownloadProvider);
    final states = ref.watch(libraryReadingStateProvider).valueOrNull;
    if (widget.editorial) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PromotionCarousel(
            cards: [
              if (episode != null && issue != null)
                EditorialStory(
                  key: ValueKey(episode.id),
                  overlayTitle: true,
                  eyebrow: issue.title,
                  item: episode,
                  onTap: download.busy || _opening
                      ? null
                      : () => _read(episode),
                  overlayActions: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: download.busy || _opening
                            ? null
                            : () => _read(episode),
                        child: Text(tr('읽기')),
                      ),
                      TextButton(
                        onPressed: download.busy || _opening
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ReaderSeriesPage(series: issue),
                                ),
                              ),
                        child: Text(tr('이번 호 전체 보기')),
                      ),
                    ],
                  ),
                ),
              ...widget.promotions,
            ],
          ),
          if (download.busy) LinearProgressIndicator(value: download.progress),
          if (result.hasError)
            TextButton(onPressed: _refresh, child: Text(tr('다시 시도'))),
          if (_preferencesLoaded)
            for (final book in compilations)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('한 달의 이야기가 한 권이 되었어요'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(book.title),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: download.busy || _opening
                                ? null
                                : () => _read(book),
                            child: Text(tr('합본 읽기')),
                          ),
                          TextButton(
                            onPressed: () => _dismiss(book),
                            child: Text(tr('확인했어요')),
                          ),
                        ],
                      ),
                      if (download.itemKey == catalogItemKey(book))
                        LinearProgressIndicator(value: download.progress),
                    ],
                  ),
                ),
              ),
        ],
      );
    }
    if (episode == null && (!_preferencesLoaded || compilations.isEmpty)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        key: const ValueKey('monthly-toggle'),
                        onTap: _savingExpansion ? null : _toggleExpanded,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 4,
                          ),
                          child: Text(
                            tr('월간 쿠피'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: TextButton(
                        onPressed: () => openReaderLink(
                          context,
                          Uri.https(
                            'www.koofy.co.kr',
                            '/monthly-koofy/submit',
                            {'lang': AppLanguage.instance.code},
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                tr('글 보내기'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.north_east, size: 14),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _savingExpansion ? null : _toggleExpanded,
                      tooltip: tr(_expanded ? '접기' : '펼치기'),
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                      ),
                    ),
                  ],
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    tr(
                      result.isLoading
                          ? '월간 쿠피를 불러오는 중입니다.'
                          : result.hasError
                          ? '월간 쿠피를 불러오지 못했습니다. 잠시 후 다시 확인해 주세요.'
                          : '이 언어로 공개된 이야기가 아직 없습니다.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_preferencesLoaded && episode != null && issue != null)
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        void submit() => openReaderLink(
                          context,
                          Uri.https(
                            'www.koofy.co.kr',
                            '/monthly-koofy/submit',
                            {'lang': AppLanguage.instance.code},
                          ),
                        );
                        return Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                key: const ValueKey('monthly-toggle'),
                                onTap: _savingExpansion
                                    ? null
                                    : _toggleExpanded,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          issue.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelLarge,
                                        ),
                                      ),
                                      if (states?[episode.bookId]?.lastReadAt ==
                                              null &&
                                          states?[episode.bookId]?.finished !=
                                              true)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          child: Text(
                                            'NEW',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              child: TextButton(
                                onPressed: submit,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: const Size(48, 48),
                                  textStyle: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        tr('글 보내기'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.north_east, size: 14),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _savingExpansion
                                  ? null
                                  : _toggleExpanded,
                              tooltip: tr(_expanded ? '접기' : '펼치기'),
                              icon: Icon(
                                _expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  if (_expanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CatalogCover(item: episode, width: 76),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  episode.episodeTitle ?? episode.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                if (episode.releaseDate.isNotEmpty)
                                  Text(
                                    episode.releaseDate.replaceAll('-', '.'),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed: download.busy || _opening
                                          ? null
                                          : () => _read(episode),
                                      child: Text(tr('읽기')),
                                    ),
                                    TextButton(
                                      onPressed: download.busy || _opening
                                          ? null
                                          : () {
                                              ref.invalidate(
                                                catalogItemsProvider(
                                                  'series:${issue.id}',
                                                ),
                                              );
                                              Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      ReaderSeriesPage(
                                                        series: issue,
                                                      ),
                                                ),
                                              );
                                            },
                                      child: Text(tr('지난 이야기')),
                                    ),
                                  ],
                                ),
                                if (download.itemKey == catalogItemKey(episode))
                                  LinearProgressIndicator(
                                    value: download.progress,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (_preferencesLoaded)
            for (final book in compilations)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('한 달의 이야기가 한 권이 되었어요'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(book.title),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: download.busy || _opening
                                ? null
                                : () => _read(book),
                            child: Text(tr('합본 읽기')),
                          ),
                          TextButton(
                            onPressed: () => _dismiss(book),
                            child: Text(tr('확인했어요')),
                          ),
                        ],
                      ),
                      if (download.itemKey == catalogItemKey(book))
                        LinearProgressIndicator(value: download.progress),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
