import 'dart:async';
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
  const MonthlyKoofySection({super.key});
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
          _preferencesLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _preferencesLoaded = true);
    }
  }

  void _refresh() {
    if (!mounted || ref.read(catalogDownloadProvider).busy || _opening) return;
    ref.invalidate(catalogItemsProvider('monthly'));
    ref.invalidate(catalogItemsProvider('book'));
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
    final issue = items.where((item) => item.kind == 'series').firstOrNull;
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
    if (episode == null && (!_preferencesLoaded || compilations.isEmpty)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (episode != null && issue != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SeriesCover(series: episode, width: 64),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('오늘의 쿠피'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          if (episode.releaseDate ==
                              DateTime.now()
                                  .toUtc()
                                  .add(const Duration(hours: 9))
                                  .toIso8601String()
                                  .substring(0, 10))
                            Text(
                              tr('새 이야기'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(
                            episode.episodeTitle ?? episode.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${issue.title} · ${episode.releaseDate}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            states?[episode.bookId]?.finished == true
                                ? tr('완독')
                                : states?[episode.bookId]?.progressLabel ??
                                      tr('아직 읽지 않은 이야기'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
                                                ReaderSeriesPage(series: issue),
                                          ),
                                        );
                                      },
                                child: Text(tr('지난 이야기')),
                              ),
                            ],
                          ),
                          if (download.itemKey == catalogItemKey(episode))
                            LinearProgressIndicator(value: download.progress),
                        ],
                      ),
                    ),
                  ],
                ),
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
