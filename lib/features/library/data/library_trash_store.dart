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
          !const ['book', 'group'].contains(item['kind'])) {
        throw const FormatException('휴지통 항목이 올바르지 않습니다.');
      }
      result[entry.key as String] = item;
    }
    return result;
  }

  Future<Set<String>> hiddenBookIds() async => {
    for (final entry in (await load()).entries)
      if (entry.value['kind'] == 'book') entry.key,
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
  Future<void> restoreBook(String id) => forget(id);
  Future<void> forget(String id) => LibraryMutations.run(() async {
    final data = await load();
    data.remove(id);
    await storage.setString(key, jsonEncode(data));
  });
}
