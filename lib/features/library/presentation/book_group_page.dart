import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_order.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/domain/library_reading_state.dart';
import 'package:koofy_reader/features/library/presentation/widgets/book_tile.dart';

class BookGroupPage extends ConsumerStatefulWidget {
  const BookGroupPage({
    super.key,
    required this.groupId,
    required this.onOpen,
    required this.onBookMenu,
    required this.onGroupMenu,
    required this.onAdd,
  });
  final String groupId;
  final Future<void> Function(Book, LibraryReadingState?) onOpen;
  final Future<void> Function(Book, LibraryReadingState?, LibraryBookStatus)
  onBookMenu;
  final Future<void> Function(BookGroup) onGroupMenu;
  final Future<void> Function(BookGroup) onAdd;
  @override
  ConsumerState<BookGroupPage> createState() => _BookGroupPageState();
}

class _BookGroupPageState extends ConsumerState<BookGroupPage> {
  bool _opening = false;
  bool _reordering = false;
  Future<void> _change(Future<Object?> Function() operation) async {
    if (_reordering) return;
    setState(() => _reordering = true);
    try {
      await operation();
      ref.invalidate(bookGroupsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('묶음 설정을 저장하지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  Future<void> _open(Book book, LibraryReadingState? state) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onOpen(book, state);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(bookGroupsProvider);
    final books = ref.watch(booksProvider).valueOrNull ?? [];
    final reading = ref.watch(libraryReadingStateProvider);
    final states = reading.valueOrNull ?? {};
    final completionAsync = ref.watch(libraryCompletionProvider);
    final completion = completionAsync.valueOrNull ?? {};
    final progressLoading = reading.isLoading || completionAsync.isLoading;
    final progressError = reading.hasError || completionAsync.hasError;
    final matches =
        groups.valueOrNull?.where((g) => g.id == widget.groupId).toList() ?? [];
    final group = matches.isEmpty ? null : matches.first;
    final byId = {for (final book in books) book.id: book};
    final members = [
      for (final id in group?.bookIds ?? <String>[])
        if (byId.containsKey(id)) byId[id]!,
    ];
    LibraryBookStatus status(Book b) => completion[b.id] == true
        ? LibraryBookStatus.finished
        : states.containsKey(b.id)
        ? LibraryBookStatus.reading
        : LibraryBookStatus.unread;
    final recent =
        members
            .where(
              (b) =>
                  states.containsKey(b.id) &&
                  status(b) != LibraryBookStatus.finished,
            )
            .toList()
          ..sort(
            (a, b) => (states[b.id]?.lastReadAt?.millisecondsSinceEpoch ?? 0)
                .compareTo(
                  states[a.id]?.lastReadAt?.millisecondsSinceEpoch ?? 0,
                ),
          );
    final finishedCount = members
        .where((b) => status(b) == LibraryBookStatus.finished)
        .length;
    final activeIndex = recent.isEmpty
        ? null
        : members.indexOf(recent.first) + 1;
    final unread = members
        .where((b) => status(b) == LibraryBookStatus.unread)
        .toList();
    final canOpen =
        reading.hasValue &&
        !reading.hasError &&
        !progressLoading &&
        !progressError &&
        !_opening;
    return Theme(
      data: KoofyTheme.forBrightness(MediaQuery.platformBrightnessOf(context)),
      child: DisplayFeatureSubScreen(
        anchorPoint: Offset.zero,
        child: Scaffold(
          appBar: AppBar(
            title: Text(group?.title ?? '책 묶음'),
            actions: [
              if (group != null)
                IconButton(
                  tooltip: '묶음 관리',
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => widget.onGroupMenu(group),
                ),
            ],
          ),
          body: SafeArea(
            child: group == null
                ? Center(
                    child: groups.isLoading
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                groups.hasError
                                    ? '묶음을 불러오지 못했습니다.'
                                    : '묶음이 해제되었습니다.',
                              ),
                              if (groups.hasError)
                                TextButton(
                                  onPressed: () =>
                                      ref.invalidate(bookGroupsProvider),
                                  child: const Text('다시 시도'),
                                ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('서재로 돌아가기'),
                              ),
                            ],
                          ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(20),
                    buildDefaultDragHandles: false,
                    header: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 72,
                              height: 104,
                              child: BookCover(
                                book: group.displayBook,
                                compact: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                progressLoading
                                    ? '읽기 기록 불러오는 중'
                                    : progressError
                                    ? '읽기 기록 확인 필요'
                                    : '총 ${members.length}권 · 완독 $finishedCount권\n${activeIndex != null
                                          ? '$activeIndex권을 읽는 중'
                                          : members.isNotEmpty && finishedCount == members.length
                                          ? '모든 권을 완독했어요'
                                          : finishedCount > 0 && unread.isNotEmpty
                                          ? '${members.indexOf(unread.first) + 1}권부터 이어 읽어보세요'
                                          : '아직 읽기 전이에요'}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!progressLoading &&
                            !progressError &&
                            members.isNotEmpty)
                          Semantics(
                            label: '총 ${members.length}권 중 $finishedCount권 완독',
                            child: LinearProgressIndicator(
                              value: finishedCount / members.length,
                            ),
                          ),
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('순서 손잡이를 끌어 읽을 순서를 바꿀 수 있어요.'),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('묶음 안의 책 표지 표시'),
                          value: group.showMemberCovers,
                          onChanged: _reordering
                              ? null
                              : (value) => _change(
                                  () => ref
                                      .read(bookGroupRepositoryProvider)
                                      .setMemberCovers(group.id, value),
                                ),
                        ),
                        TextButton.icon(
                          onPressed: _reordering || members.length < 2
                              ? null
                              : () => _change(() {
                                  final sorted = [...members]
                                    ..sort(
                                      (a, b) =>
                                          compareBookTitles(a.title, b.title),
                                    );
                                  return ref
                                      .read(bookGroupRepositoryProvider)
                                      .reorder(
                                        group.id,
                                        sorted.map((b) => b.id).toList(),
                                        availableIds: byId.keys.toSet(),
                                      );
                                }),
                          icon: const Icon(Icons.sort),
                          label: const Text('제목·회차 순으로 정렬'),
                        ),
                        if (recent.isNotEmpty)
                          FilledButton.icon(
                            key: const ValueKey('group-continue'),
                            onPressed: canOpen
                                ? () => _open(
                                    recent.first,
                                    states[recent.first.id],
                                  )
                                : null,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: Text('${recent.first.title} · 이어 읽기'),
                          ),
                        if (recent.isEmpty && unread.isNotEmpty)
                          FilledButton.icon(
                            key: const ValueKey('group-start'),
                            onPressed: canOpen
                                ? () => _open(
                                    unread.first,
                                    states[unread.first.id],
                                  )
                                : null,
                            icon: const Icon(Icons.menu_book_outlined),
                            label: Text('${unread.first.title} · 읽기 시작'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => widget.onAdd(group),
                          icon: const Icon(Icons.add),
                          label: const Text('묶음에 책 추가'),
                        ),
                        if (progressLoading) const LinearProgressIndicator(),
                        if (progressError)
                          TextButton(
                            onPressed: () {
                              ref.invalidate(libraryReadingStateProvider);
                              ref.invalidate(libraryCompletionProvider);
                            },
                            child: const Text('읽기 기록 다시 불러오기'),
                          ),
                        if (members.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('비어 있는 묶음입니다. 책을 추가하거나 묶음을 해제할 수 있어요.'),
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                    itemCount: members.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (_reordering) return;
                      setState(() => _reordering = true);
                      try {
                        final ids = members.map((b) => b.id).toList();
                        if (newIndex > oldIndex) newIndex--;
                        ids.insert(newIndex, ids.removeAt(oldIndex));
                        await ref
                            .read(bookGroupRepositoryProvider)
                            .reorder(
                              group.id,
                              ids,
                              availableIds: byId.keys.toSet(),
                            );
                        ref.invalidate(bookGroupsProvider);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('순서를 저장하지 못했습니다. 다시 시도해 주세요.'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _reordering = false);
                      }
                    },
                    itemBuilder: (context, index) {
                      final book = members[index];
                      final state = states[book.id];
                      return ListTile(
                        key: ValueKey('group-book-${book.id}'),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: !group.showMemberCovers
                            ? null
                            : SizedBox(
                                width: 42,
                                height: 60,
                                child: BookCover(book: book, compact: true),
                              ),
                        title: Text('${index + 1}. ${book.title}'),
                        subtitle: Text(
                          progressError
                              ? '읽기 기록 확인 필요'
                              : progressLoading
                              ? '기록 불러오는 중'
                              : switch (status(book)) {
                                  LibraryBookStatus.finished => '완독',
                                  LibraryBookStatus.unread => '아직 읽지 않음',
                                  LibraryBookStatus.reading =>
                                    '읽는 중 · ${state?.progressLabel ?? '위치 저장됨'}',
                                },
                        ),
                        onTap: canOpen ? () => _open(book, state) : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '${book.title} 더보기',
                              icon: const Icon(Icons.more_horiz),
                              onPressed: () =>
                                  widget.onBookMenu(book, state, status(book)),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              enabled: !_reordering,
                              child: Semantics(
                                label: '${book.title} 순서 변경',
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
