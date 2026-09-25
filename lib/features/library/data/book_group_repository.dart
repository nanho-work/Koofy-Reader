import 'dart:convert';
import 'dart:math';

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
  final groupsFuture = ref.watch(bookGroupRepositoryProvider).load();
  final covers = ref.watch(groupCoverStoreProvider);
  final results = await Future.wait<Object>([booksFuture, groupsFuture]);
  final books = results[0] as List<Book>;
  final ids = books.map((book) => book.id).toSet();
  final groups = (results[1] as List<BookGroup>)
      .map(
        (group) =>
            group.copyWith(bookIds: group.bookIds.where(ids.contains).toList()),
      )
      .toList();
  final covered = await covers.apply(groups.map((g) => g.displayBook).toList());
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
  Future<void> _pending = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

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

  Future<List<BookGroup>> load() async =>
      _decode(await storage.getString(storageKey));

  Future<GroupChange> _change(
    void Function(List<BookGroup>) edit, {
    List<String> removed = const [],
  }) => _serial(() async {
    final before = await storage.getString(storageKey);
    final groups = _decode(before);
    edit(groups);
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

  Future<GroupChange> create(String title, List<String> ids) => _change((
    groups,
  ) {
    if (ids.length < 2) throw ArgumentError('책을 두 권 이상 선택해 주세요.');
    _requireUngrouped(groups, ids);
    groups.add(
      BookGroup(id: 'group_${_newId()}', title: _title(title), bookIds: ids),
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
  Future<GroupChange> dissolve(String id) => _change((groups) {
    groups.removeAt(_index(groups, id));
  }, removed: [id]);
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
    return true;
  });
}
