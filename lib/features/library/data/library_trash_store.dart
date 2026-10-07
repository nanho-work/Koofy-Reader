import 'dart:convert';
import 'package:koofy_reader/core/storage/library_mutations.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';

class LibraryTrashStore {
  LibraryTrashStore(this.storage);
  final LocalStorage storage;
  static const key = 'library_trash_v1';
  Future<Map<String, Map<String, dynamic>>> load() async {
    final raw = await storage.getString(key);
    if (raw == null || raw.isEmpty) return {};
    final data = jsonDecode(raw);
    if (data is! Map) throw const FormatException('휴지통 정보를 읽을 수 없습니다.');
    final result = <String, Map<String, dynamic>>{};
    for (final entry in data.entries) {
      final item = Map<String, dynamic>.from(entry.value as Map);
      if (item['title'] is! String ||
          item['deletedAt'] is! String ||
          !const ['book', 'group', 'bundle'].contains(item['kind'])) {
        throw const FormatException('휴지통 항목이 올바르지 않습니다.');
      }
      if (item['kind'] == 'bundle' &&
          (item['books'] is! List ||
              (item['books'] as List).any((id) => id is! String) ||
              item['group'] is! Map)) {
        throw const FormatException('묶음 휴지통 정보가 올바르지 않습니다.');
      }
      result[entry.key as String] = item;
    }
    return result;
  }

  Future<Set<String>> hiddenBookIds() async => {
    for (final entry in (await load()).entries)
      if (entry.value['kind'] == 'book') entry.key,
    for (final entry in (await load()).values)
      if (entry['kind'] == 'bundle') ...(entry['books'] as List).cast<String>(),
  };
  Future<Set<String>> hiddenGroupIds() async => {
    for (final entry in (await load()).values)
      if (entry['kind'] == 'bundle' && entry['keepShelf'] != true)
        entry['group']['id'] as String,
  };
  Future<void> moveBook(Book book) => _put(book.id, book.title, 'book', null);
  Future<void> keepGroup(BookGroup group) =>
      _put(group.id, group.title, 'group', group.toJson());
  Future<void> _put(
    String id,
    String title,
    String kind,
    Map<String, dynamic>? group,
  ) => LibraryMutations.run(() async {
    final data = await load();
    data[id] = {
      'title': title,
      'kind': kind,
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
      if (group != null) 'group': group,
    };
    await storage.setString(key, jsonEncode(data));
  });
  Future<void> ensureRestorable(String id) async {
    final data = await load();
    for (final entry in data.entries) {
      if (entry.key == id ||
          (entry.value['kind'] == 'bundle' &&
              (entry.value['books'] as List).contains(id))) {
        if (entry.value['deleting'] == true) {
          throw StateError('영구 삭제 중인 항목입니다. 휴지통에서 삭제를 완료해 주세요.');
        }
      }
    }
  }

  Future<void> restoreBook(String id) => LibraryMutations.run(() async {
    final data = await load();
    await ensureRestorable(id);
    data.remove(id);
    for (final entry in data.values) {
      if (entry['kind'] == 'bundle') {
        entry['books'] = (entry['books'] as List)
            .where((value) => value != id)
            .toList();
      }
    }
    await save(data);
  });
  Future<void> save(Map<String, Map<String, dynamic>> data) =>
      storage.setString(key, jsonEncode(data));
  Future<String> keepBundle(
    BookGroup group,
    List<String> ids, {
    required bool keepShelf,
  }) => LibraryMutations.run(() async {
    final data = await load();
    final id = 'trash_${DateTime.now().microsecondsSinceEpoch}_${group.id}';
    data[id] = {
      'title': group.title,
      'kind': 'bundle',
      'deletedAt': DateTime.now().toUtc().toIso8601String(),
      'group': group.toJson(),
      'books': ids,
      'keepShelf': keepShelf,
    };
    await save(data);
    return id;
  });
  Future<void> forget(String id) => LibraryMutations.run(() async {
    final data = await load();
    data.remove(id);
    await storage.setString(key, jsonEncode(data));
  });
}
