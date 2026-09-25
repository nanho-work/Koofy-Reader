part of 'library_page.dart';

extension _LibraryGroups on _LibraryPageState {
  List<Book> _ungroupedBooks() {
    final groups = ref.read(bookGroupsProvider).valueOrNull;
    if (groups == null || ref.read(bookGroupsProvider).hasError) {
      throw StateError('묶음 목록을 먼저 불러와 주세요.');
    }
    final ids = groups.expand((g) => g.bookIds).toSet();
    return (ref.read(booksProvider).valueOrNull ?? <Book>[])
        .where((b) => !ids.contains(b.id))
        .toList()
      ..sort((a, b) => compareBookTitles(a.title, b.title));
  }

  Future<void> _createGroup({
    List<String> initialIds = const [],
    String title = '',
  }) async {
    if (_groupBusy) return;
    try {
      final books = _ungroupedBooks();
      if (books.length < 2) {
        _snack('묶이지 않은 책이 두 권 이상 있어야 합니다.');
        return;
      }
      final selection = await Navigator.of(context).push<GroupSelection>(
        MaterialPageRoute(
          builder: (_) => Theme(
            data: KoofyTheme.forBrightness(
              MediaQuery.platformBrightnessOf(context),
            ),
            child: BookGroupEditor(
              books: books,
              initialIds: initialIds,
              initialTitle: title,
            ),
          ),
        ),
      );
      if (!mounted || selection == null) return;
      await _changeGroup(
        () => ref
            .read(bookGroupRepositoryProvider)
            .create(selection.title, selection.ids),
        '책 묶음을 만들었습니다.',
      );
      _clearShelfFilters();
    } catch (_) {
      _snack('묶음을 만들지 못했습니다. 목록을 새로고침해 주세요.');
    }
  }

  Future<void> _addGroupBooks(BookGroup group) async {
    if (_groupBusy) return;
    try {
      final books = _ungroupedBooks();
      if (books.isEmpty) {
        _snack('추가할 수 있는 책이 없습니다. 다른 묶음의 책은 먼저 꺼내 주세요.');
        return;
      }
      final selection = await Navigator.of(context).push<GroupSelection>(
        MaterialPageRoute(
          builder: (_) => Theme(
            data: KoofyTheme.forBrightness(
              MediaQuery.platformBrightnessOf(context),
            ),
            child: BookGroupEditor(books: books, creating: false),
          ),
        ),
      );
      if (!mounted || selection == null) return;
      await _changeGroup(
        () =>
            ref.read(bookGroupRepositoryProvider).add(group.id, selection.ids),
        '묶음에 추가했습니다.',
      );
    } catch (_) {
      _snack('책을 추가하지 못했습니다. 목록을 새로고침해 주세요.');
    }
  }

  Future<void> _chooseGroup(Book book) async {
    final groups = ref.read(bookGroupsProvider).valueOrNull ?? [];
    if (groups.isEmpty) {
      await _createGroup(initialIds: [book.id], title: book.title);
      return;
    }
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('추가할 묶음 선택')),
            for (final group in groups)
              ListTile(
                title: Text(group.title),
                subtitle: Text('${group.bookIds.length}권'),
                onTap: () => Navigator.pop(context, group.id),
              ),
          ],
        ),
      ),
    );
    if (!mounted || id == null) return;
    await _changeGroup(
      () => ref.read(bookGroupRepositoryProvider).add(id, [book.id]),
      '묶음에 추가했습니다.',
    );
  }

  Future<void> _openGroup(BookGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookGroupPage(
          groupId: group.id,
          onOpen: _openReader,
          onBookMenu: _bookMenu,
          onGroupMenu: _groupMenu,
          onAdd: _addGroupBooks,
        ),
      ),
    );
  }

  Future<void> _groupMenu(BookGroup group) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(group.title),
                subtitle: Text('${group.bookIds.length}권의 책 묶음'),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('묶음에 책 추가'),
                onTap: () => Navigator.pop(context, 'add'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('묶음 이름 변경'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: Text(
                  group.coverPath == null ? '표지 이미지 등록' : '표지 이미지 변경',
                ),
                onTap: () => Navigator.pop(context, 'cover'),
              ),
              if (group.coverPath != null)
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('표지 초기화'),
                  onTap: () => Navigator.pop(context, 'reset'),
                ),
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('묶음 해제'),
                subtitle: const Text('책은 모두 서재로 돌아갑니다.'),
                onTap: () => Navigator.pop(context, 'dissolve'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'add':
        await _addGroupBooks(group);
      case 'rename':
        final name = await _groupName(group.title);
        if (!mounted || name == null) return;
        await _changeGroup(
          () => ref.read(bookGroupRepositoryProvider).rename(group.id, name),
          '묶음 이름을 변경했습니다.',
        );
      case 'cover':
        await _groupCover(group);
      case 'reset':
        await _groupCover(group, reset: true);
      case 'dissolve':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('묶음 해제'),
            content: Text(
              '“${group.title}”의 책 ${group.bookIds.length}권을 서재로 꺼낼까요? 책과 읽던 위치는 유지됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('묶음 해제'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        await _changeGroup(
          () => ref.read(bookGroupRepositoryProvider).dissolve(group.id),
          '묶음을 해제했습니다. 책은 서재에 있습니다.',
        );
    }
  }

  Future<String?> _groupName(String name) {
    var value = name;
    return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('묶음 이름 변경'),
          content: TextFormField(
            initialValue: name,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '묶음 이름'),
            onChanged: (text) => update(() => value = text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: value.trim().isEmpty
                  ? null
                  : () => Navigator.pop(context, value.trim()),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _groupCover(BookGroup group, {bool reset = false}) async {
    if (_groupBusy) return;
    _setGroupBusy(true);
    try {
      final covers = ref.read(groupCoverStoreProvider);
      if (reset) {
        await covers.reset(group.id);
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        );
        if (!mounted || result == null) return;
        final path = result.files.single.path;
        if (path == null) {
          _snack('이미지를 열 수 없습니다.');
          return;
        }
        await covers.setImage(group.id, path);
      }
      if (!mounted) return;
      ref.invalidate(bookGroupsProvider);
      _snack(reset ? '기본 표지로 되돌렸습니다.' : '묶음 표지를 적용했습니다.');
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('표지를 저장하지 못했습니다. 다른 이미지로 다시 시도해 주세요.');
    } finally {
      _setGroupBusy(false);
    }
  }

  Future<void> _changeGroup(
    Future<GroupChange> Function() action,
    String message,
  ) async {
    if (_groupBusy) return;
    _setGroupBusy(true);
    try {
      final repository = ref.read(bookGroupRepositoryProvider);
      final covers = ref.read(groupCoverStoreProvider);
      final change = await action();
      if (!mounted) return;
      ref.invalidate(bookGroupsProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      final snack = messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '실행 취소',
            onPressed: () async {
              try {
                final undone = await repository.undo(change);
                if (!mounted) return;
                ref.invalidate(bookGroupsProvider);
                if (!undone) _snack('이후에 묶음을 변경해서 되돌릴 수 없습니다.');
              } catch (_) {
                _snack('실행 취소를 저장하지 못했습니다. 다시 확인해 주세요.');
              }
            },
          ),
        ),
      );
      // Keep the group cover during Undo; clean it up only after Undo expires.
      if (change.removedGroupIds.isNotEmpty) {
        snack.closed.then((reason) async {
          if (reason == SnackBarClosedReason.action) return;
          try {
            final remaining = (await repository.load())
                .map((g) => g.id)
                .toSet();
            for (final id in change.removedGroupIds) {
              if (!remaining.contains(id)) await covers.reset(id);
            }
          } catch (_) {
            /* Cleanup can be retried without changing membership. */
          }
        });
      }
    } catch (_) {
      _snack('묶음 변경을 저장하지 못했습니다. 목록을 새로고침한 뒤 다시 시도해 주세요.');
    } finally {
      _setGroupBusy(false);
    }
  }

  Widget _groupDropTarget(Book book, BookGroup? group, Widget tile) {
    final child = group != null
        ? tile
        : LongPressDraggable<Book>(
            data: book,
            maxSimultaneousDrags: _groupBusy ? 0 : 1,
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 90,
                height: 130,
                child: BookCover(book: book, compact: true),
              ),
            ),
            childWhenDragging: Opacity(opacity: .35, child: tile),
            child: tile,
          );
    return DragTarget<Book>(
      onWillAcceptWithDetails: (details) =>
          !_groupBusy && details.data.id != book.id,
      onAcceptWithDetails: (details) async {
        if (group == null) {
          await _createGroup(
            initialIds: [book.id, details.data.id],
            title: book.title,
          );
        } else {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('묶음에 추가'),
              content: Text(
                '“${details.data.title}”을 “${group.title}”에 추가할까요?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('추가'),
                ),
              ],
            ),
          );
          if (!mounted || confirmed != true) return;
          await _changeGroup(
            () => ref.read(bookGroupRepositoryProvider).add(group.id, [
              details.data.id,
            ]),
            '묶음에 추가했습니다.',
          );
        }
      },
      builder: (context, candidates, rejected) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: candidates.isEmpty
              ? null
              : Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
        ),
        child: child,
      ),
    );
  }
}
