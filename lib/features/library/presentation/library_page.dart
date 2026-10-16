import 'package:koofy_reader/core/localization/language_button.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:koofy_reader/features/library/application/cover_matching.dart';
import 'package:koofy_reader/features/library/presentation/batch_cover_page.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/library_trash_store.dart';
import 'package:koofy_reader/features/library/presentation/text_import_preview.dart';
import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureType, DisplayFeatureState;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_page.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/application/book_import.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/presentation/book_group_editor.dart';
import 'package:koofy_reader/features/library/presentation/book_group_page.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_order.dart';
import 'package:koofy_reader/features/library/domain/library_reading_state.dart';
import 'package:koofy_reader/features/library/presentation/widgets/book_tile.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';
import 'package:koofy_reader/features/native_reader/presentation/legacy_records_page.dart';

part 'library_groups.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchExpanded = false;
  final _scroll = ScrollController();
  final _sidebarScroll = ScrollController();
  bool _downloadsExpanded = false;
  bool _catalogVisited = false;
  LibraryBookStatus? _filter;
  bool _titleSort = false;
  bool _importing = false;
  String _importProgress = tr("가져오는 중…");
  bool _opening = false;
  bool _updatingCover = false;
  bool _groupBusy = false;

  void _setGroupBusy(bool value) {
    if (mounted) setState(() => _groupBusy = value);
  }

  void _clearShelfFilters() {
    if (mounted) {
      setState(() {
        _filter = null;
        _search.clear();
      });
    }
  }

  ({double width, String bookId, double rowFraction, bool scrolled})?
  _gridAnchor;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _sidebarScroll.dispose();
    super.dispose();
  }

  void _refreshProgress() {
    if (ref.read(nativeLibraryPositionsProvider).hasError) {
      // Retrying a derived FutureProvider alone would reuse a failed service.
      ref.invalidate(nativeReaderServicesProvider);
    }
    ref.invalidate(legacyReadingProgressProvider);
    ref.invalidate(nativeLibraryPositionsProvider);
  }

  Future<void> _refresh() async {
    ref.invalidate(booksProvider);
    ref.invalidate(bookGroupsProvider);
    ref.invalidate(libraryCompletionProvider);
    _refreshProgress();
    try {
      await Future.wait<Object>([
        ref.read(booksProvider.future),
        ref.read(libraryReadingStateProvider.future),
      ]);
    } catch (_) {
      /* The screen keeps previous data and presents retry. */
    }
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(
      context,
    ); // Rebuild app-owned labels when language changes.
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    // Horizontal hinges (tabletop posture) must not cut through the app. Narrow
    // dual screens use a single safe panel; wide vertical folds use two panes.
    final avoidFeatures = media.displayFeatures
        .where(
          (feature) =>
              (feature.type == DisplayFeatureType.hinge ||
                  (feature.type == DisplayFeatureType.fold &&
                      feature.state ==
                          DisplayFeatureState.postureHalfOpened)) &&
              (feature.bounds.width > feature.bounds.height ||
                  feature.bounds.left < 280 ||
                  media.size.width - feature.bounds.right < 300),
        )
        .toList();
    return Theme(
      data: theme,
      child: MediaQuery(
        data: media.copyWith(displayFeatures: avoidFeatures),
        child: DisplayFeatureSubScreen(
          anchorPoint: Offset.zero,
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                toolbarHeight: 48,
                actions: [
                  const LanguageButton(),
                  IconButton(
                    tooltip: tr("책 묶음 만들기"),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: _groupBusy ? null : () => _createGroup(),
                  ),
                  IconButton(
                    tooltip: tr("설정"),
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.settings),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: SafeArea(
                top: false,
                child: _body(
                  context,
                  avoidFeatures.isEmpty ? media : MediaQuery.of(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MediaQueryData media) {
    final booksAsync = ref.watch(booksProvider);
    final groupsAsync = ref.watch(bookGroupsProvider);
    final readingAsync = ref.watch(libraryReadingStateProvider);
    final completion =
        ref.watch(libraryCompletionProvider).valueOrNull ??
        const <String, bool>{};
    final books = booksAsync.valueOrNull;
    if (books == null || !groupsAsync.hasValue) {
      final content = booksAsync.hasError || groupsAsync.hasError
          ? _message(
              context,
              tr("서재를 불러오지 못했습니다."),
              action: tr("다시 시도"),
              onAction: _refresh,
            )
          : Center(
              child: CircularProgressIndicator(semanticsLabel: tr("서재 불러오는 중")),
            );
      return MediaQuery(
        data: media,
        child: DisplayFeatureSubScreen(
          anchorPoint: Offset.zero,
          child: content,
        ),
      );
    }
    final states = {...?readingAsync.valueOrNull};
    final groups = {
      for (final group in groupsAsync.requireValue) group.id: group,
    };
    final groupedIds = groups.values.expand((g) => g.bookIds).toSet();
    final groupCovers = {
      for (final group in groups.values)
        if (group.coverPath != null)
          for (final bookId in group.bookIds) bookId: group.coverPath!,
    };
    for (final group in groups.values) {
      final memberStates =
          group.bookIds
              .map((id) => states[id])
              .whereType<LibraryReadingState>()
              .toList()
            ..sort(
              (a, b) => (b.lastReadAt?.millisecondsSinceEpoch ?? 0).compareTo(
                a.lastReadAt?.millisecondsSinceEpoch ?? 0,
              ),
            );
      if (memberStates.isNotEmpty) states[group.id] = memberStates.first;
    }
    // Never open a book at a guessed position while its saved state is unknown.
    final canOpen =
        readingAsync.hasValue &&
        !readingAsync.hasError &&
        !readingAsync.isLoading &&
        !_opening;
    LibraryBookStatus status(Book book) {
      final group = groups[book.id];
      if (group != null) {
        if (group.bookIds.isNotEmpty &&
            group.bookIds.every((id) => completion[id] == true)) {
          return LibraryBookStatus.finished;
        }
        if (group.bookIds.any(
          (id) => states.containsKey(id) || completion[id] == true,
        )) {
          return LibraryBookStatus.reading;
        }
        return LibraryBookStatus.unread;
      }
      return completion[book.id] == true
          ? LibraryBookStatus.finished
          : states.containsKey(book.id)
          ? LibraryBookStatus.reading
          : LibraryBookStatus.unread;
    }

    final recent = books.where((b) => states.containsKey(b.id)).toList()
      ..sort((a, b) => _compareRecent(a, b, states));
    Book? nextRecentBook;
    if (recent.isNotEmpty &&
        (states[recent.first.id]!.finished ||
            completion[recent.first.id] == true)) {
      for (final group in groups.values) {
        final index = group.bookIds.indexOf(recent.first.id);
        if (index >= 0 && index + 1 < group.bookIds.length) {
          final nextId = group.bookIds[index + 1];
          nextRecentBook = books.where((book) => book.id == nextId).firstOrNull;
          break;
        }
      }
    }
    final query = _search.text.trim().toLowerCase();
    final visible =
        [
              ...books.where((book) => !groupedIds.contains(book.id)),
              ...groups.values.map((g) => g.displayBook),
            ]
            .where(
              (b) =>
                  (_filter == null || status(b) == _filter) &&
                  ('${b.title} ${b.author}'.toLowerCase().contains(query) ||
                      (groups[b.id]?.bookIds.any(
                            (id) => books.any(
                              (member) =>
                                  member.id == id &&
                                  '${member.title} ${member.author}'
                                      .toLowerCase()
                                      .contains(query),
                            ),
                          ) ??
                          false)),
            )
            .toList()
          ..sort(
            (a, b) => _titleSort
                ? compareBookTitles(a.title, b.title)
                : _compareRecent(a, b, states),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final hinges = media.displayFeatures.where(
          (f) =>
              (f.type == DisplayFeatureType.hinge ||
                  f.type == DisplayFeatureType.fold) &&
              f.bounds.height > f.bounds.width &&
              f.bounds.left >= 280 &&
              media.size.width - f.bounds.right >= 300,
        );
        final hinge = hinges.isEmpty ? null : hinges.first.bounds;
        final wide = width >= 720 || hinge != null;
        final leftWidth = hinge == null
            ? math.min(340.0, width * .4)
            : hinge.left - media.padding.left;
        final gap = hinge == null ? 12.0 : hinge.width;
        final intro = Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: recent.isNotEmpty
              ? _continueReading(
                  context,
                  recent.first,
                  states[recent.first.id]!,
                  canOpen,
                  groupCoverPath: groupCovers[recent.first.id],
                  nextBook: nextRecentBook,
                  nextState: states[nextRecentBook?.id],
                )
              : _welcome(context, empty: books.isEmpty),
        );
        final shelf = _shelf(
          context,
          visible,
          states,
          status,
          canOpen,
          progressLoading: readingAsync.isLoading,
          progressError: readingAsync.hasError,
          groups: groups,
        );
        final shelfScroll = RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            key: const PageStorageKey('library-scroll'),
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (booksAsync.hasError ||
                  groupsAsync.hasError ||
                  readingAsync.hasError)
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: wide ? leftWidth : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              booksAsync.hasError || groupsAsync.hasError
                                  ? tr("서재를 새로 불러오지 못했습니다.")
                                  : tr("읽기 기록을 불러오지 못했습니다. 다시 시도해 주세요."),
                            ),
                            TextButton(
                              onPressed: _refresh,
                              child: Text(tr("다시 시도")),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (!wide) ...[
                SliverToBoxAdapter(child: intro),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: _libraryActions(context, wide: false),
                  ),
                ),
              ],
              if (books.isNotEmpty || groups.isNotEmpty) shelf,
              SliverToBoxAdapter(
                child: SizedBox(height: 28 + AdOverlayInsets.bottomOf(context)),
              ),
            ],
          ),
        );
        if (!wide) return shelfScroll;
        return Row(
          key: const ValueKey('library-two-pane'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: leftWidth,
              child: CustomScrollView(
                key: const PageStorageKey('library-sidebar-scroll'),
                controller: _sidebarScroll,
                slivers: [
                  SliverToBoxAdapter(
                    child: _downloadsExpanded
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                            child: OutlinedButton.icon(
                              key: const ValueKey('expand-reading'),
                              onPressed: () => _showDownloads(false),
                              icon: const Icon(Icons.expand_more),
                              label: Text(
                                recent.isNotEmpty
                                    ? tr("읽던 책: {0}", [recent.first.title])
                                    : tr("책 읽기"),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        : intro,
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 8,
                      ),
                      child: _libraryActions(context, wide: true),
                    ),
                  ),
                  SliverLayoutBuilder(
                    builder: (context, constraints) => SliverToBoxAdapter(
                      child: Visibility(
                        visible: _downloadsExpanded,
                        maintainState: true,
                        child: SizedBox(
                          // Use the space below the actual menu heights. On very
                          // short screens, the entire sidebar can scroll instead
                          // of clipping the reader card or squeezing the catalog.
                          height: math.max(
                            280,
                            constraints.viewportMainAxisExtent -
                                constraints.precedingScrollExtent,
                          ),
                          child: _catalogVisited
                              ? const ReaderCatalogBrowser()
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: AdOverlayInsets.bottomOf(context)),
                  ),
                ],
              ),
            ),
            SizedBox(width: gap),
            Expanded(child: shelfScroll),
          ],
        );
      },
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchExpanded = !_searchExpanded;
      if (!_searchExpanded) _search.clear();
    });
    if (_searchExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchExpanded) _searchFocus.requestFocus();
      });
    } else {
      _searchFocus.unfocus();
    }
  }

  Widget _libraryActions(BuildContext context, {required bool wide}) {
    void download() => wide
        ? _showDownloads(!_downloadsExpanded)
        : Navigator.pushNamed(context, AppRoutes.catalog);
    final downloadKey = ValueKey(wide ? 'toggle-downloads' : 'open-downloads');
    final addEnabled = !_importing && !_updatingCover;
    const duration = Duration(milliseconds: 240);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final space = math.max(0.0, box.maxWidth - 64);
            final searchWidth = math.max(48.0, box.maxWidth - 112);
            return TweenAnimationBuilder<double>(
              tween: Tween(end: _searchExpanded ? 1 : 0),
              duration: duration,
              curve: Curves.easeOutCubic,
              builder: (context, progress, _) {
                final compact = _searchExpanded || progress > .01;
                return Row(
                  children: [
                    SizedBox(
                      width: 48 + (searchWidth - 48) * progress,
                      child: ClipRect(
                        child: OverflowBox(
                          fit: OverflowBoxFit.deferToChild,
                          alignment: Alignment.centerLeft,
                          minWidth: _searchExpanded ? searchWidth : 48,
                          maxWidth: _searchExpanded ? searchWidth : 48,
                          child: _searchExpanded
                              ? TextField(
                                  key: const ValueKey('library-search-field'),
                                  controller: _search,
                                  focusNode: _searchFocus,
                                  onChanged: (_) => setState(() {}),
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) => _searchFocus.unfocus(),
                                  decoration: InputDecoration(
                                    hintText: tr('내 서재에서 책 검색'),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    suffixIcon: IconButton(
                                      tooltip: tr('검색 닫기'),
                                      icon: const Icon(Icons.close),
                                      onPressed: _toggleSearch,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  key: const ValueKey('open-library-search'),
                                  tooltip: tr('서재 검색'),
                                  icon: const Icon(Icons.search),
                                  onPressed: _toggleSearch,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: space * .65 + (48 - space * .65) * progress,
                      child: compact
                          ? IconButton.outlined(
                              key: downloadKey,
                              tooltip: tr('도서·글꼴 다운로드'),
                              icon: const Icon(Icons.download_outlined),
                              onPressed: download,
                            )
                          : OutlinedButton.icon(
                              key: downloadKey,
                              onPressed: download,
                              icon: const Icon(
                                Icons.download_outlined,
                                size: 18,
                              ),
                              label: Text(tr('도서·글꼴 다운로드')),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: space * .35 + (48 - space * .35) * progress,
                      child: compact
                          ? IconButton.outlined(
                              key: const ValueKey('add-books'),
                              tooltip: tr('책 추가'),
                              icon: const Icon(Icons.library_add_outlined),
                              onPressed: addEnabled ? _importBook : null,
                            )
                          : OutlinedButton.icon(
                              key: const ValueKey('add-books'),
                              onPressed: addEnabled ? _importBook : null,
                              icon: const Icon(
                                Icons.library_add_outlined,
                                size: 18,
                              ),
                              label: Text(tr('책 추가')),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
        if (_importing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_importProgress),
          ),
      ],
    );
  }

  void _showDownloads(bool expanded) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_sidebarScroll.hasClients) _sidebarScroll.jumpTo(0);
    setState(() {
      _downloadsExpanded = expanded;
      if (expanded) _catalogVisited = true;
    });
  }

  int _compareRecent(Book a, Book b, Map<String, LibraryReadingState> states) {
    final aState = states[a.id];
    final bState = states[b.id];
    if (aState == null && bState != null) return 1;
    if (aState != null && bState == null) return -1;
    final time = (bState?.lastReadAt?.millisecondsSinceEpoch ?? 0).compareTo(
      aState?.lastReadAt?.millisecondsSinceEpoch ?? 0,
    );
    return time != 0 ? time : compareBookTitles(a.title, b.title);
  }

  Widget _welcome(BuildContext context, {required bool empty}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(tr("나만의 작은 서재"), style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 10),
      Text(
        empty ? tr("첫 번째 책을\n들여놓아 볼까요?") : tr("오늘은 어떤 이야기를\n읽어 볼까요?"),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 1.4),
      ),
      const SizedBox(height: 12),
      Text(
        empty
            ? tr("기기에 있는 EPUB · TXT 파일을 가져오세요.")
            : tr("책을 열면 다음부터 읽던 곳으로 이어집니다."),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (empty) ...[
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _importing || _updatingCover ? null : _importBook,
          icon: const Icon(Icons.add),
          label: Text(_importing ? _importProgress : tr("첫 책 가져오기")),
        ),
      ],
    ],
  );

  Widget _continueReading(
    BuildContext context,
    Book book,
    LibraryReadingState state,
    bool canOpen, {
    String? groupCoverPath,
    Book? nextBook,
    LibraryReadingState? nextState,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('continue-reading-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant, width: .7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 108,
                child: BookCover(
                  // The displayed group cover never changes the book opened.
                  book: book.coverPath == null && groupCoverPath != null
                      ? book.withCoverPath(groupCoverPath)
                      : book,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      book.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            state.finished
                                ? tr("완독")
                                : state.progression != null &&
                                      !state.needsMigration
                                ? '${(state.progression! * 100).floor()}%'
                                : state.progressLabel,
                            key: const ValueKey('continue-reading-status'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              key: const ValueKey('continue-reading-button'),
                              onPressed: canOpen
                                  ? () => _openReader(book, state)
                                  : null,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              child: Text(tr("이어 읽기")),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (state.progression != null) ...[
                      LinearProgressIndicator(
                        value: state.progression,
                        minHeight: 2,
                        semanticsLabel: tr("{0} 읽은 비율", [book.title]),
                        semanticsValue: state.progressLabel,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (nextBook != null) ...[
            const SizedBox(height: 12),
            Text(
              tr("다음 회차: {0}", [nextBook.title]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('continue-next-book'),
              onPressed: canOpen
                  ? () => _openReader(nextBook, nextState)
                  : null,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(tr("다음 회차 읽기")),
            ),
          ],
        ],
      ),
    );
  }

  Widget _shelf(
    BuildContext context,
    List<Book> books,
    Map<String, LibraryReadingState> states,
    LibraryBookStatus Function(Book) status,
    bool canOpen, {
    required bool progressLoading,
    required bool progressError,
    required Map<String, BookGroup> groups,
  }) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in <LibraryBookStatus?, String>{
                      null: tr("전체"),
                      LibraryBookStatus.reading: tr("읽는 중"),
                      LibraryBookStatus.unread: tr("읽을 책"),
                      LibraryBookStatus.finished: tr("완독"),
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _filter == entry.key,
                        onSelected: (_) => setState(() => _filter = entry.key),
                      ),
                  ],
                ),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      books.any((b) => groups.containsKey(b.id))
                          ? tr("{0}권 · {1}묶음", [
                              books
                                  .where((b) => !groups.containsKey(b.id))
                                  .length,
                              books
                                  .where((b) => groups.containsKey(b.id))
                                  .length,
                            ])
                          : tr("{0}권", [books.length]),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _importing || _updatingCover
                              ? null
                              : _batchCovers,
                          icon: const Icon(
                            Icons.collections_outlined,
                            size: 18,
                          ),
                          label: Text(tr("표지 일괄 등록")),
                        ),
                        PopupMenuButton<bool>(
                          tooltip: tr("책 정렬"),
                          initialValue: _titleSort,
                          onSelected: (value) =>
                              setState(() => _titleSort = value),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: false,
                              child: Text(tr("최근 읽은 순")),
                            ),
                            PopupMenuItem(value: true, child: Text(tr("제목순"))),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_titleSort ? tr("제목순") : tr("최근 읽은 순")),
                                const Icon(Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (progressLoading)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      semanticsLabel: tr("읽기 기록 불러오는 중"),
                    ),
                  ),
                if (books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        Text(tr("조건에 맞는 책이 없어요.")),
                        TextButton(
                          onPressed: () => setState(() {
                            _filter = null;
                            _search.clear();
                          }),
                          child: Text(tr("전체 책 보기")),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              // Keep the user's shelf density stable on both foldable panels
              // and the cover screen. Card content adapts to the column width.
              const count = 3;
              const spacing = 12.0;
              final tileWidth =
                  (constraints.crossAxisExtent - (count - 1) * spacing) / count;
              final extent = math.min(tileWidth * 1.4, 270) + 92 * scale;
              final previous = _gridAnchor;
              if (books.isNotEmpty) {
                final row = constraints.scrollOffset / (extent + 24);
                final index = (row.floor() * count).clamp(0, books.length - 1);
                _gridAnchor = (
                  width: constraints.crossAxisExtent,
                  bookId: books[index].id,
                  rowFraction: row - row.floor(),
                  scrolled: constraints.scrollOffset > 0,
                );
                if (previous != null &&
                    previous.scrolled &&
                    (previous.width - constraints.crossAxisExtent).abs() > 1) {
                  final anchorIndex = books.indexWhere(
                    (book) => book.id == previous.bookId,
                  );
                  if (anchorIndex >= 0) {
                    final target =
                        constraints.precedingScrollExtent +
                        ((anchorIndex ~/ count) + previous.rowFraction) *
                            (extent + 24);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _scroll.hasClients) {
                        _scroll.jumpTo(
                          target.clamp(0, _scroll.position.maxScrollExtent),
                        );
                      }
                    });
                  }
                }
              } else {
                _gridAnchor = null;
              }
              return SliverGrid.builder(
                itemCount: books.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: 24,
                  mainAxisExtent: extent,
                ),
                itemBuilder: (context, index) {
                  final book = books[index];
                  final state = states[book.id];
                  final group = groups[book.id];
                  return _groupDropTarget(
                    book,
                    group,
                    BookTile(
                      key: ValueKey(book.id),
                      book: book,
                      enableLongPress: false,
                      badge: group == null
                          ? null
                          : tr("{0}권 묶음", [group.bookIds.length]),
                      onTap: group != null
                          ? () => _openGroup(group)
                          : canOpen
                          ? () => _openReader(book, state)
                          : null,
                      onMore: () => group != null
                          ? _groupMenu(group)
                          : _bookMenu(book, state, status(book)),
                      statusLabel: progressError
                          ? tr("읽기 기록 확인 필요")
                          : progressLoading
                          ? tr("기록 불러오는 중")
                          : group != null
                          ? tr("완독 {0}/{1}권", [
                              group.bookIds
                                  .where(
                                    (id) =>
                                        ref
                                            .read(libraryCompletionProvider)
                                            .valueOrNull?[id] ==
                                        true,
                                  )
                                  .length,
                              group.bookIds.length,
                            ])
                          : switch (status(book)) {
                              LibraryBookStatus.finished => tr("완독"),
                              LibraryBookStatus.unread => tr("아직 읽지 않음"),
                              LibraryBookStatus.reading =>
                                state?.progressLabel ?? tr("읽는 중"),
                            },
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _message(
    BuildContext context,
    String text, {
    required String action,
    required VoidCallback onAction,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );

  Future<void> _openReader(Book book, LibraryReadingState? state) async {
    if (_opening) return;
    if (!ref.read(nativeReaderAvailableProvider)) {
      _snack(tr("독서 화면은 Android와 iOS 앱에서 사용할 수 있습니다."));
      return;
    }
    setState(() => _opening = true);
    try {
      await Navigator.pushNamed(
        context,
        AppRoutes.nativeReader,
        arguments: book,
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
        _refreshProgress();
      }
    }
  }

  Future<void> _bookMenu(
    Book book,
    LibraryReadingState? state,
    LibraryBookStatus status,
  ) async {
    final membership =
        (ref.read(bookGroupsProvider).valueOrNull ?? <BookGroup>[])
            .where((g) => g.bookIds.contains(book.id))
            .toList();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(book.title), subtitle: Text(book.author)),
              if (membership.isEmpty) ...[
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: Text(tr("책 묶음 만들기")),
                  onTap: () => Navigator.pop(context, 'createGroup'),
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outlined),
                  title: Text(tr("묶음에 추가")),
                  onTap: () => Navigator.pop(context, 'addToGroup'),
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.move_to_inbox_outlined),
                  title: Text(tr("묶음에서 꺼내기")),
                  onTap: () => Navigator.pop(context, 'takeOut'),
                ),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: Text(
                  book.coverPath == null && book.coverAssetPath == null
                      ? tr("표지 이미지 등록")
                      : tr("표지 이미지 변경"),
                ),
                enabled: !_updatingCover,
                onTap: () => Navigator.pop(context, 'cover'),
              ),
              if (book.coverPath != null)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text(tr("표지 초기화")),
                  subtitle: Text(
                    book.coverAssetPath != null
                        ? tr("처음 제공된 표지로 되돌립니다.")
                        : tr("제목이 표시되는 기본 표지로 되돌립니다."),
                  ),
                  enabled: !_updatingCover,
                  onTap: () => Navigator.pop(context, 'resetCover'),
                ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(
                  status == LibraryBookStatus.finished
                      ? tr("완독 표시 해제")
                      : tr("완독으로 표시"),
                ),
                onTap: () => Navigator.pop(context, 'completion'),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(tr("이전 버전의 독서 기록")),
                subtitle: Text(tr("보존된 기록을 확인하고 읽던 곳을 찾습니다.")),
                onTap: () => Navigator.pop(context, 'history'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(book.isLocalFile ? tr("책 삭제") : tr("서재에서 숨기기")),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'createGroup':
        await _createGroup(initialIds: [book.id], title: book.title);
      case 'addToGroup':
        await _chooseGroup(book);
      case 'takeOut':
        await _changeGroup(
          () => ref
              .read(bookGroupRepositoryProvider)
              .takeOut(membership.single.id, book.id),
          tr("서재로 꺼냈습니다."),
        );
      case 'cover':
        await _updateCover(book);
      case 'resetCover':
        await _updateCover(book, reset: true);
      case 'completion':
        try {
          await ref
              .read(libraryCompletionRepositoryProvider)
              .setFinished(book.id, status != LibraryBookStatus.finished);
          if (mounted) ref.invalidate(libraryCompletionProvider);
        } catch (_) {
          _snack(tr("완독 표시를 저장하지 못했습니다. 다시 시도해 주세요."));
        }
      case 'history':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LegacyRecordsPage(book: book),
          ),
        );
        if (mounted) _refreshProgress();
      case 'remove':
        await _confirmRemoveBook(book);
    }
  }

  Future<void> _confirmRemoveBook(Book book) async {
    final action = book.isLocalFile ? tr("삭제") : tr("숨김");
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr("책 {0}", [action])),
        content: Text(
          tr("“{0}”을 휴지통으로 옮길까요? 파일·표지·읽던 위치는 유지되며 설정의 휴지통에서 복원할 수 있습니다.", [
            book.title,
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr("취소")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      final trash = LibraryTrashStore(ref.read(localStorageProvider));
      await trash.moveBook(book);
      if (!mounted) return;
      ref.invalidate(booksProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr("휴지통으로 이동: {0}", [book.title])),
          action: SnackBarAction(
            label: tr("실행 취소"),
            onPressed: () async {
              try {
                await trash.restoreBook(book.id);
                if (mounted) ref.invalidate(booksProvider);
              } catch (_) {
                _snack(tr("복원하지 못했습니다. 설정의 휴지통에서 다시 시도해 주세요."));
              }
            },
          ),
        ),
      );
    } catch (_) {
      _snack(tr("책을 제거하지 못했습니다. 다시 시도해 주세요."));
    }
  }

  Future<void> _updateCover(Book book, {bool reset = false}) async {
    if (_updatingCover || _importing) return;
    if (kIsWeb) {
      _snack(tr("표지 이미지는 Android · iOS 앱에서 등록해 주세요."));
      return;
    }
    setState(() => _updatingCover = true);
    try {
      final repository = ref.read(bookRepositoryProvider);
      if (reset) {
        await repository.resetBookCover(book.id);
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
          dialogTitle: tr("표지 이미지 선택"),
        );
        if (!mounted || result == null || result.files.isEmpty) return;
        final path = result.files.single.path;
        if (path == null) {
          _snack(tr("이미지를 열 수 없습니다. 다른 이미지를 선택해 주세요."));
          return;
        }
        await repository.setBookCover(book.id, path);
      }
      if (!mounted) return;
      ref.invalidate(booksProvider);
      _snack(reset ? tr("기본 표지로 되돌렸습니다.") : tr("표지 이미지를 적용했습니다."));
    } on FormatException catch (error) {
      _snack(tr(error.message));
    } catch (_) {
      _snack(tr("표지를 저장하지 못했습니다. JPG · PNG · WebP 이미지로 다시 시도해 주세요."));
    } finally {
      if (mounted) setState(() => _updatingCover = false);
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _batchCovers() async {
    if (_updatingCover || _importing) return;
    setState(() => _updatingCover = true);
    try {
      await showBatchCovers(context, ref);
    } finally {
      if (mounted) setState(() => _updatingCover = false);
    }
  }

  Future<void> _importBook() async {
    if (_importing || _updatingCover) return;
    if (kIsWeb) {
      _snack(tr("파일 가져오기는 Android · iOS 앱에서 이용해 주세요."));
      return;
    }
    setState(() {
      _importing = true;
      _importProgress = tr("파일 선택 중…");
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'epub', ...coverImageExtensions],
        allowMultiple: true,
        dialogTitle: tr("책과 같은 이름의 표지 이미지 함께 선택"),
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final selected = result.files
          .map((f) => BookImportFile(f.name, f.path))
          .toList();
      final images = selected
          .where((f) => coverImageExtensions.contains(fileExtension(f.name)))
          .toList();
      final bookFiles = selected
          .where((f) => !coverImageExtensions.contains(fileExtension(f.name)))
          .toList();
      if (bookFiles.isEmpty) {
        await showBatchCovers(context, ref, images: images);
        return;
      }
      setState(() => _importProgress = tr("가져오는 중 0/{0}", [bookFiles.length]));
      final imported = await importBooks(
        ref.read(bookRepositoryProvider),
        bookFiles,
        importFile: (path) => importWithTextPreview(
          context,
          ref.read(bookRepositoryProvider),
          path,
        ),
        onProgress: (completed, total) {
          if (mounted) {
            setState(
              () => _importProgress = tr("가져오는 중 {0}/{1}", [completed, total]),
            );
          }
        },
      );
      if (!mounted) return;
      ref.invalidate(booksProvider);
      setState(() {
        _filter = null;
        _search.clear();
      });
      final summary = [
        tr("가져오기 완료: {0}권 추가", [imported.added]),
        if (imported.existing > 0) tr(' · 이미 등록된 책 {0}권', [imported.existing]),
        if (imported.skipped > 0) tr(' · 건너뛴 파일 {0}개', [imported.skipped]),
      ].join();
      if (imported.failedNames.isEmpty) {
        _snack(summary);
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr("가져오기 결과")),
            content: SingleChildScrollView(
              child: Text(
                tr("{0}\n\n다음 {1}개 파일은 가져오지 못했습니다. ", [
                      summary,
                      imported.failedNames.length,
                    ]) +
                    tr("파일이 기기에 내려받아져 있는지, TXT·EPUB 형식인지 확인해 주세요.\n\n") +
                    imported.failedNames.join('\n'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr("확인")),
              ),
            ],
          ),
        );
      }
      if (mounted && images.isNotEmpty) {
        await showBatchCovers(
          context,
          ref,
          images: images,
          bookIds: imported.importedIds.toSet(),
        );
      }
      if (mounted && bookFiles.length > 1 && imported.addedIds.isNotEmpty) {
        await _organizeImportedBooks(imported.addedIds);
      }
    } catch (_) {
      _snack(tr("책을 가져오지 못했습니다. 파일을 확인하고 다시 시도해 주세요."));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
