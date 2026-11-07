import 'library_trash_store.dart';
import 'dart:convert';
import 'dart:math';
import 'package:koofy_reader/core/storage/library_mutations.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

final bookGroupRepositoryProvider = Provider(
  (ref) => BookGroupRepository(ref.watch(localStorageProvider)),
);
final groupCoverStoreProvider = Provider(
  (ref) => BookCoverStore(ref.watch(localStorageProvider)),
);
final bookGroupsProvider = FutureProvider<List<BookGroup>>((ref) async {
  final booksFuture = ref.watch(booksProvider.future);
  final repository = ref.watch(bookGroupRepositoryProvider);
  final covers = ref.watch(groupCoverStoreProvider);
  final storage = ref.watch(localStorageProvider);
  final books = await booksFuture;
  final localBooks = {for (final book in books) book.id: book};
  await repository.syncCatalogSeries(books);
  final hiddenGroups = await LibraryTrashStore(storage).hiddenGroupIds();
  final groups = (await repository.load())
      .where((group) => !hiddenGroups.contains(group.id))
      .map(
        (group) => group.copyWith(
          bookIds: group.bookIds.where(localBooks.containsKey).toList(),
        ),
      )
      .toList();
  final covered = await covers.apply([
    for (final group in groups)
      if (group.catalogSeriesId != null && group.bookIds.isNotEmpty)
        group.displayBook.withCoverPath(
          localBooks[group.bookIds.first]?.coverPath,
        )
      else
        group.displayBook,
  ]);
  return [
    for (var i = 0; i < groups.length; i++)
      groups[i].copyWith(coverPath: covered[i].coverPath),
  ];
});

class GroupChange {
  const GroupChange(this.before, this.after, {this.removedGroupIds = const []});
  final String? before;
  final String after;
  final List<String> removedGroupIds;
}

/// Only group membership is written here. Book files, covers and locators keep
/// their original book IDs. Serial writes and revision checks protect Undo.
class BookGroupRepository {
  BookGroupRepository(this.storage);
  final LocalStorage storage;
  static const storageKey = 'library_book_groups_v1';
  static const _seriesMigrationKey = 'library_catalog_series_groups_v1';
  Future<T> _serial<T>(Future<T> Function() operation) =>
      LibraryMutations.run(operation);

  List<BookGroup> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final value = jsonDecode(raw);
    if (value is! Map || value['groups'] is! List) {
      throw const FormatException('묶음 목록을 읽을 수 없습니다.');
    }
    final groups = (value['groups'] as List)
        .map((g) => BookGroup.fromJson(Map<String, dynamic>.from(g as Map)))
        .toList();
    final groupIds = <String>{};
    final bookIds = <String>{};
    for (final group in groups) {
      if (!groupIds.add(group.id) ||
          group.bookIds.any((id) => !bookIds.add(id))) {
        throw const FormatException('중복된 책 묶음 정보입니다.');
      }
    }
    return groups;
  }

  Future<List<BookGroup>> load() => LibraryMutations.run(
    () async => _decode(await storage.getString(storageKey)),
  );

  Future<GroupChange> _change(
    void Function(List<BookGroup>) edit, {
    List<String> removed = const [],
    bool skipUnchanged = false,
  }) => _serial(() async {
    final before = await storage.getString(storageKey);
    final groups = _decode(before);
    final previousGroups = skipUnchanged ? jsonEncode(groups) : null;
    edit(groups);
    if (previousGroups != null && previousGroups == jsonEncode(groups)) {
      return GroupChange(before, before ?? '');
    }
    final after = jsonEncode({
      'revision': _newId(),
      'groups': groups.map((g) => g.toJson()).toList(),
    });
    await storage.setString(storageKey, after);
    return GroupChange(before, after, removedGroupIds: removed);
  });

  String _newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String _title(String value) {
    final title = value.trim();
    if (title.isEmpty || title.length > 100) {
      throw ArgumentError('묶음 이름은 1~100자로 입력해 주세요.');
    }
    return title;
  }

  int _index(List<BookGroup> groups, String id) {
    final index = groups.indexWhere((g) => g.id == id);
    if (index < 0) throw StateError('묶음을 찾지 못했습니다.');
    return index;
  }

  void _requireUngrouped(List<BookGroup> groups, List<String> ids) {
    if (ids.isEmpty ||
        ids.toSet().length != ids.length ||
        groups.any((g) => g.bookIds.any(ids.contains))) {
      throw StateError('이미 묶인 책은 먼저 묶음에서 꺼내 주세요.');
    }
  }

  /// Migrate existing series once. Later downloads add only that episode so
  /// taking a book out of a bundle remains a reader choice.
  Future<void> syncCatalogSeries(
    List<Book> books, {
    String? downloadedBookId,
  }) => _serial(() async {
    final migrating = downloadedBookId == null;
    if (migrating && await storage.getString(_seriesMigrationKey) == 'done') {
      return;
    }

    final episodes = <String, List<({Book book, int number, String title})>>{};
    for (final book in books) {
      final metadata = book.catalogMetadata;
      final seriesId = metadata?['seriesId'];
      final number = metadata?['episodeNumber'];
      final title = metadata?['seriesTitle'];
      final month = metadata?['issueMonth'];
      final monthly = month is String && month.isNotEmpty;
      if (seriesId is! String ||
          seriesId.isEmpty ||
          number is! int ||
          (migrating && monthly)) {
        continue;
      }
      final groupId = BookGroup.catalogId(seriesId, monthly: monthly);
      episodes.putIfAbsent(groupId, () => []).add((
        book: book,
        number: number,
        title: title is String && title.trim().isNotEmpty
            ? title.trim()
            : monthly
            ? month
            : book.title,
      ));
    }
    if (episodes.isNotEmpty) {
      await _change((groups) {
        final occupied = groups.expand((group) => group.bookIds).toSet();
        for (final entry in episodes.entries) {
          final additions = entry.value
              .where(
                (episode) =>
                    (migrating || episode.book.id == downloadedBookId) &&
                    !occupied.contains(episode.book.id),
              )
              .toList();
          if (additions.isEmpty) continue;
          final index = groups.indexWhere((group) => group.id == entry.key);
          final old = index < 0 ? null : groups[index];
          final order = {
            for (final episode in entry.value) episode.book.id: episode.number,
          };
          final ids =
              [...?old?.bookIds, ...additions.map((episode) => episode.book.id)]
                ..sort((a, b) {
                  final ai = order[a], bi = order[b];
                  if (ai == null || bi == null) {
                    return ai == null ? (bi == null ? a.compareTo(b) : 1) : -1;
                  }
                  final byNumber = ai.compareTo(bi);
                  return byNumber == 0 ? a.compareTo(b) : byNumber;
                });
          if (old == null) {
            final title = additions.first.title;
            groups.add(
              BookGroup(
                id: entry.key,
                title: title.length > 100 ? title.substring(0, 100) : title,
                bookIds: ids,
                showMemberCovers: true,
              ),
            );
          } else {
            groups[index] = old.copyWith(bookIds: ids);
          }
        }
      }, skipUnchanged: true);
    }
    if (migrating) await storage.setString(_seriesMigrationKey, 'done');
  });

  Future<GroupChange> create(String title, List<String> ids, {String? id}) =>
      _change((groups) {
        if (ids.length < 2) throw ArgumentError('책을 두 권 이상 선택해 주세요.');
        _requireUngrouped(groups, ids);
        if (id != null &&
            (!id.startsWith('group_') || groups.any((g) => g.id == id))) {
          throw StateError('묶음 목록이 바뀌었습니다. 다시 시도해 주세요.');
        }
        groups.add(
          BookGroup(
            id: id ?? 'group_${_newId()}',
            title: _title(title),
            bookIds: ids,
          ),
        );
      });
  Future<GroupChange> add(String groupId, List<String> ids) =>
      _change((groups) {
        _requireUngrouped(groups, ids);
        final index = _index(groups, groupId);
        groups[index] = groups[index].copyWith(
          bookIds: [...groups[index].bookIds, ...ids],
        );
      });
  Future<GroupChange> rename(String id, String title) => _change((groups) {
    final index = _index(groups, id);
    groups[index] = groups[index].copyWith(title: _title(title));
  });
  Future<GroupChange> setMemberCovers(String id, bool show) =>
      _change((groups) {
        final index = _index(groups, id);
        groups[index] = groups[index].copyWith(showMemberCovers: show);
      });
  Future<GroupChange> takeOut(String id, String bookId) => _change((groups) {
    final index = _index(groups, id);
    groups[index] = groups[index].copyWith(
      bookIds: groups[index].bookIds.where((b) => b != bookId).toList(),
    );
  });
  Future<GroupChange> dissolve(String id) => _serial(() async {
    final current = await load();
    await LibraryTrashStore(storage).keepGroup(current[_index(current, id)]);
    return _change((groups) {
      groups.removeAt(_index(groups, id));
    }, removed: [id]);
  });

  Future<void> trashGroup(String id, {required bool keepShelf}) =>
      _serial(() async {
        final groups = await load();
        final group = groups[_index(groups, id)];
        final trash = LibraryTrashStore(storage);
        final hidden = await trash.hiddenBookIds();
        final ids = group.bookIds.where((id) => !hidden.contains(id)).toList();
        if (keepShelf && ids.isEmpty) return;
        await trash.keepBundle(group, ids, keepShelf: keepShelf);
        await _change((groups) {
          final index = _index(groups, id);
          if (keepShelf) {
            groups[index] = groups[index].copyWith(bookIds: []);
          } else {
            groups.removeAt(index);
          }
        });
      });

  Future<void> restoreBundle(String entryId) => _serial(() async {
    final trash = LibraryTrashStore(storage);
    final data = await trash.load();
    final entry = data[entryId];
    if (entry == null) return;
    if (entry['deleting'] == true) throw StateError('영구 삭제 중인 항목은 복원할 수 없습니다.');
    final group = BookGroup.fromJson(
      Map<String, dynamic>.from(entry['group'] as Map),
    );
    final available = (await LocalBookRepository(
      storage,
    ).allStoredBooks()).map((book) => book.id).toSet();
    await _change((groups) {
      final index = groups.indexWhere((value) => value.id == group.id);
      final occupied = groups
          .where((value) => value.id != group.id)
          .expand((value) => value.bookIds)
          .toSet();
      final prior = index < 0 ? group.copyWith(bookIds: []) : groups[index];
      final ids = <String>{
        ...group.bookIds.where(
          (id) => available.contains(id) && !occupied.contains(id),
        ),
        ...prior.bookIds,
      };
      final restored = prior.copyWith(bookIds: ids.toList());
      if (index < 0) {
        groups.add(restored);
      } else {
        groups[index] = restored;
      }
    });
    await trash.forget(entryId);
  });

  Future<void> finishTrashedGroup(String id) async {
    await _change((groups) => groups.removeWhere((group) => group.id == id));
  }

  Future<void> forgetBooks(Set<String> ids) => _change((groups) {
    for (var i = 0; i < groups.length; i++) {
      groups[i] = groups[i].copyWith(
        bookIds: groups[i].bookIds.where((id) => !ids.contains(id)).toList(),
      );
    }
  });

  Future<void> restoreGroup(BookGroup group, Set<String> availableIds) =>
      _serial(() async {
        await _change((groups) {
          if (groups.any((g) => g.id == group.id)) return;
          final occupied = groups.expand((g) => g.bookIds).toSet();
          groups.add(
            group.copyWith(
              bookIds: group.bookIds
                  .where(
                    (id) => availableIds.contains(id) && !occupied.contains(id),
                  )
                  .toList(),
            ),
          );
        });
        await LibraryTrashStore(storage).forget(group.id);
      });
  Future<GroupChange> reorder(
    String id,
    List<String> ids, {
    Set<String>? availableIds,
  }) => _change((groups) {
    final index = _index(groups, id);
    final previous = groups[index].bookIds
        .where((id) => availableIds == null || availableIds.contains(id))
        .toList();
    if (previous.length != ids.length ||
        ids.toSet().length != ids.length ||
        !ids.toSet().containsAll(previous)) {
      throw StateError('책 목록이 바뀌었습니다. 다시 시도해 주세요.');
    }
    groups[index] = groups[index].copyWith(bookIds: ids);
  });
  Future<bool> undo(GroupChange change) => _serial(() async {
    if (await storage.getString(storageKey) != change.after) return false;
    await storage.setString(storageKey, change.before ?? '');
    for (final id in change.removedGroupIds) {
      await LibraryTrashStore(storage).forget(id);
    }
    return true;
  });
}
