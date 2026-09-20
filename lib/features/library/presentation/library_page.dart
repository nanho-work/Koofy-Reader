import 'dart:math' as math;
import 'dart:ui' show DisplayFeatureType, DisplayFeatureState;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/presentation/book_group_editor.dart';
import 'package:koofy_reader/features/library/presentation/book_group_page.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
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
  final _scroll = ScrollController();
  LibraryBookStatus? _filter;
  bool _searching = false;
  bool _titleSort = false;
  bool _importing = false;
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
    _scroll.dispose();
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
    final media = MediaQuery.of(context);
    final theme = KoofyTheme.forBrightness(media.platformBrightness);
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
                title: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KOOFY',
                      style: TextStyle(fontSize: 11, letterSpacing: 2),
                    ),
                    Text(
                      '내 서재',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                toolbarHeight: 76,
                actions: [
                  IconButton(
                    tooltip: '책 묶음 만들기',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: _groupBusy ? null : () => _createGroup(),
                  ),
                  IconButton(
                    tooltip: '책 · 글꼴 다운로드',
                    icon: const Icon(Icons.cloud_download_outlined),
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.catalog),
                  ),
                  IconButton(
                    tooltip: '서재 검색',
                    icon: Icon(_searching ? Icons.search_off : Icons.search),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _search.clear();
                    }),
                  ),
                  IconButton(
                    tooltip: '설정',
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
              '서재를 불러오지 못했습니다.',
              action: '다시 시도',
              onAction: _refresh,
            )
          : const Center(
              child: CircularProgressIndicator(semanticsLabel: '서재 불러오는 중'),
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

    final recent =
        books
            .where(
              (b) =>
                  states.containsKey(b.id) &&
                  status(b) != LibraryBookStatus.finished,
            )
            .toList()
          ..sort((a, b) => _compareRecent(a, b, states));
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
                ? a.title.compareTo(b.title)
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
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
          child: recent.isNotEmpty
              ? _continueReading(
                  context,
                  recent.first,
                  states[recent.first.id]!,
                  canOpen,
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
        return RefreshIndicator(
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
                                  ? '서재를 새로 불러오지 못했습니다.'
                                  : '읽기 기록을 불러오지 못했습니다. 다시 시도해 주세요.',
                            ),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (wide)
                SliverCrossAxisGroup(
                  key: const ValueKey('library-two-pane'),
                  slivers: [
                    SliverConstrainedCrossAxis(
                      maxExtent: leftWidth,
                      sliver: SliverToBoxAdapter(child: intro),
                    ),
                    SliverConstrainedCrossAxis(
                      maxExtent: gap,
                      sliver: const SliverToBoxAdapter(
                        child: SizedBox.shrink(),
                      ),
                    ),
                    if (books.isNotEmpty || groups.isNotEmpty)
                      shelf
                    else
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                  ],
                )
              else ...[
                SliverToBoxAdapter(child: intro),
                if (books.isNotEmpty || groups.isNotEmpty) shelf,
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        );
      },
    );
  }

  int _compareRecent(Book a, Book b, Map<String, LibraryReadingState> states) {
    final aState = states[a.id];
    final bState = states[b.id];
    if (aState == null && bState != null) return 1;
    if (aState != null && bState == null) return -1;
    final time = (bState?.lastReadAt?.millisecondsSinceEpoch ?? 0).compareTo(
      aState?.lastReadAt?.millisecondsSinceEpoch ?? 0,
    );
    return time != 0 ? time : a.title.compareTo(b.title);
  }

  Widget _welcome(BuildContext context, {required bool empty}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('나만의 작은 서재', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 10),
      Text(
        empty ? '첫 번째 책을\n들여놓아 볼까요?' : '오늘은 어떤 이야기를\n읽어 볼까요?',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 1.4),
      ),
      const SizedBox(height: 12),
      Text(
        empty ? '기기에 있는 EPUB · TXT 파일을 가져오세요.' : '책을 열면 다음부터 읽던 곳으로 이어집니다.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      if (empty) ...[
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _importing ? null : _importBook,
          icon: const Icon(Icons.add),
          label: Text(_importing ? '가져오는 중…' : '첫 책 가져오기'),
        ),
      ],
    ],
  );

  Widget _continueReading(
    BuildContext context,
    Book book,
    LibraryReadingState state,
    bool canOpen,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '이어 읽기',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('continue-reading-card'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(20),
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
                    child: BookCover(book: book, compact: true),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          book.author,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (state.chapterTitle != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            state.chapterTitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (state.progression != null) ...[
                LinearProgressIndicator(
                  value: state.progression,
                  minHeight: 3,
                  semanticsLabel: '${book.title} 읽은 비율',
                  semanticsValue: state.progressLabel,
                ),
                const SizedBox(height: 10),
              ],
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    state.progressLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    _dateLabel(state.lastReadAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: canOpen ? () => _openReader(book, state) : null,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('이어 읽기'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return '저장된 독서 기록';
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days <= 0) return '오늘 읽었어요';
    if (days == 1) return '어제 읽었어요';
    return '${date.year}.${date.month}.${date.day}';
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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Text('나의 책', style: Theme.of(context).textTheme.titleLarge),
                    OutlinedButton.icon(
                      onPressed: _importing ? null : _importBook,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(_importing ? '가져오는 중…' : '책 가져오기'),
                    ),
                  ],
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '제목 또는 작가 검색',
                        prefixIcon: const Icon(Icons.search),

                        suffixIcon: IconButton(
                          tooltip: '검색어 지우기',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(_search.clear),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final entry in <LibraryBookStatus?, String>{
                      null: '전체',
                      LibraryBookStatus.reading: '읽는 중',
                      LibraryBookStatus.unread: '읽을 책',
                      LibraryBookStatus.finished: '완독',
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
                  children: [
                    Text(
                      books.any((b) => groups.containsKey(b.id))
                          ? '${books.where((b) => !groups.containsKey(b.id)).length}권 · ${books.where((b) => groups.containsKey(b.id)).length}묶음'
                          : '${books.length}권',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    PopupMenuButton<bool>(
                      tooltip: '책 정렬',
                      initialValue: _titleSort,
                      onSelected: (value) => setState(() => _titleSort = value),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: false, child: Text('최근 읽은 순')),
                        PopupMenuItem(value: true, child: Text('제목순')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_titleSort ? '제목순' : '최근 읽은 순'),
                            const Icon(Icons.expand_more, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (progressLoading)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(
                      semanticsLabel: '읽기 기록 불러오는 중',
                    ),
                  ),
                if (books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        const Text('조건에 맞는 책이 없어요.'),
                        TextButton(
                          onPressed: () => setState(() {
                            _filter = null;
                            _search.clear();
                          }),
                          child: const Text('전체 책 보기'),
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
                          : '${group.bookIds.length}권 묶음',
                      onTap: group != null
                          ? () => _openGroup(group)
                          : canOpen
                          ? () => _openReader(book, state)
                          : null,
                      onMore: () => group != null
                          ? _groupMenu(group)
                          : _bookMenu(book, state, status(book)),
                      statusLabel: group != null
                          ? '${group.bookIds.length}권'
                          : progressError
                          ? '읽기 기록 확인 필요'
                          : progressLoading
                          ? '기록 불러오는 중'
                          : switch (status(book)) {
                              LibraryBookStatus.finished => '완독',
                              LibraryBookStatus.unread => '아직 읽지 않음',
                              LibraryBookStatus.reading =>
                                state?.progressLabel ?? '읽는 중',
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
      _snack('독서 화면은 Android와 iOS 앱에서 사용할 수 있습니다.');
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
                  title: const Text('책 묶음 만들기'),
                  onTap: () => Navigator.pop(context, 'createGroup'),
                ),
                ListTile(
                  leading: const Icon(Icons.drive_file_move_outlined),
                  title: const Text('묶음에 추가'),
                  onTap: () => Navigator.pop(context, 'addToGroup'),
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.move_to_inbox_outlined),
                  title: const Text('묶음에서 꺼내기'),
                  onTap: () => Navigator.pop(context, 'takeOut'),
                ),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: Text(book.coverPath == null ? '표지 이미지 등록' : '표지 이미지 변경'),
                enabled: !_updatingCover,
                onTap: () => Navigator.pop(context, 'cover'),
              ),
              if (book.coverPath != null)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('표지 초기화'),
                  subtitle: const Text('제목이 표시되는 기본 표지로 되돌립니다.'),
                  enabled: !_updatingCover,
                  onTap: () => Navigator.pop(context, 'resetCover'),
                ),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text(
                  status == LibraryBookStatus.finished ? '완독 표시 해제' : '완독으로 표시',
                ),
                onTap: () => Navigator.pop(context, 'completion'),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('이전 버전의 독서 기록'),
                subtitle: const Text('보존된 기록을 확인하고 읽던 곳을 찾습니다.'),
                onTap: () => Navigator.pop(context, 'history'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(book.isLocalFile ? '책 삭제' : '서재에서 숨기기'),
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
          '서재로 꺼냈습니다.',
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
          _snack('완독 표시를 저장하지 못했습니다. 다시 시도해 주세요.');
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
    final action = book.isLocalFile ? '삭제' : '숨김';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('책 $action'),
        content: Text(
          '서재에서 “${book.title}” 책을 ${book.isLocalFile ? '삭제' : '숨김 처리'}할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
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
      final groupsRepository = ref.read(bookGroupRepositoryProvider);
      final removed = await ref
          .read(bookRepositoryProvider)
          .removeBookFromLibrary(book.id);
      if (removed) {
        for (final group in await groupsRepository.load()) {
          if (group.bookIds.contains(book.id)) {
            await groupsRepository.takeOut(group.id, book.id);
          }
        }
      }
      if (!mounted) return;
      ref.invalidate(booksProvider);
      _snack(removed ? '$action 완료: ${book.title}' : '제거할 책을 찾지 못했습니다.');
    } catch (_) {
      _snack('책을 제거하지 못했습니다. 다시 시도해 주세요.');
    }
  }

  Future<void> _updateCover(Book book, {bool reset = false}) async {
    if (_updatingCover) return;
    if (kIsWeb) {
      _snack('표지 이미지는 Android · iOS 앱에서 등록해 주세요.');
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
          dialogTitle: '표지 이미지 선택',
        );
        if (!mounted || result == null || result.files.isEmpty) return;
        final path = result.files.single.path;
        if (path == null) {
          _snack('이미지를 열 수 없습니다. 다른 이미지를 선택해 주세요.');
          return;
        }
        await repository.setBookCover(book.id, path);
      }
      if (!mounted) return;
      ref.invalidate(booksProvider);
      _snack(reset ? '기본 표지로 되돌렸습니다.' : '표지 이미지를 적용했습니다.');
    } on FormatException catch (error) {
      _snack(error.message);
    } catch (_) {
      _snack('표지를 저장하지 못했습니다. JPG · PNG · WebP 이미지로 다시 시도해 주세요.');
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

  Future<void> _importBook() async {
    if (_importing) return;
    if (kIsWeb) {
      _snack('파일 가져오기는 Android · iOS 앱에서 이용해 주세요.');
      return;
    }
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'epub'],
      );
      if (!mounted || result == null) return;
      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        _snack('파일 경로를 읽을 수 없습니다.');
        return;
      }
      final book = await ref.read(bookRepositoryProvider).importBookFile(path);
      if (!mounted) return;
      if (book == null) {
        _snack('TXT 또는 EPUB 파일만 가져올 수 있습니다.');
        return;
      }
      ref.invalidate(booksProvider);
      setState(() {
        _filter = null;
        _search.clear();
      });
      _snack('가져오기 완료: ${book.title}');
    } catch (_) {
      _snack('책을 가져오지 못했습니다. 파일을 확인하고 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}
