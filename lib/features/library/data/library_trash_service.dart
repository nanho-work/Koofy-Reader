import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/library_mutations.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/core/utils/hash_utils.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_trash_store.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';

final libraryTrashServiceProvider = FutureProvider<LibraryTrashService>((
  ref,
) async {
  final native = await ref.watch(nativeReaderServicesProvider.future);
  return LibraryTrashService(
    ref.watch(localStorageProvider),
    native.supportDirectory!,
    beforeDelete: () async {
      if (native.coordinator.activeSessionId != null) {
        throw StateError('읽는 책을 먼저 닫아 주세요.');
      }
    },
    deleteReadingRecords: (ids) async {
      if (native.coordinator.activeSessionId != null) {
        throw StateError('읽는 책을 먼저 닫아 주세요.');
      }
      await native.coordinator.store.deleteBooks(ids);
    },
  );
});

/// All deletions are explicit, serialized, and limited to owned, unshared files.
/// A durable pending entry prevents partial cleanup from becoming restorable.
class LibraryTrashService {
  LibraryTrashService(
    this.storage,
    this.support, {
    required this.deleteReadingRecords,
    this.beforeDelete,
  });
  final LocalStorage storage;
  final Directory support;
  final Future<void> Function(Set<String>) deleteReadingRecords;
  final Future<void> Function()? beforeDelete;
  LibraryTrashStore get trash => LibraryTrashStore(storage);
  String _hash(String id) => sha256.convert(utf8.encode(id)).toString();
  String _coverKey(String id) =>
      'library_cover_${base64Url.encode(utf8.encode(id))}';
  Set<String> _bookIds(String key, Map<String, dynamic> entry) =>
      entry['kind'] == 'book'
      ? {key}
      : entry['kind'] == 'bundle'
      ? (entry['books'] as List).cast<String>().toSet()
      : {};

  Future<bool> _owned(String value) async {
    final path = File(value).absolute.uri.normalizePath().toFilePath();
    final root = support.absolute.path;
    final prefixes = [
      'library_sources/',
      'cloud_reader/books/',
      'book_covers/',
      'native_reader_v1/publications/',
      'native_reader_v1/legacy_cache/',
      'reader_content_cache/',
      'library_backups/restore-',
    ];
    if (!prefixes.any((prefix) => path.startsWith('$root/$prefix'))) {
      return false;
    }
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      return false;
    }
    if (!await File(path).exists()) return true;
    final realRoot = await support.resolveSymbolicLinks();
    final real = await File(path).resolveSymbolicLinks();
    return prefixes.any((prefix) => real.startsWith('$realRoot/$prefix'));
  }

  Future<Set<String>> _files(Set<String> ids, Set<String> ownerIds) async {
    final books = await LocalBookRepository(storage).allStoredBooks();
    final covers = await storage.getStringEntriesByPrefix('library_cover_');
    final candidates = <String>{};
    final protected = <String>{};
    for (final book in books) {
      final paths = [book.localPath, book.coverPath].whereType<String>();
      (ids.contains(book.id) ? candidates : protected).addAll(paths);
    }
    for (final cover in covers.entries) {
      if (!RegExp(r'^[a-f0-9]{32}\.png$').hasMatch(cover.value)) continue;
      (ownerIds.any((id) => _coverKey(id) == cover.key)
              ? candidates
              : protected)
          .add('${support.path}/book_covers/${cover.value}');
    }
    final references = Directory(
      '${support.path}/native_reader_v1/publications/references',
    );
    final hashes = <String>{}, protectedHashes = <String>{};
    if (await references.exists()) {
      await for (final file in references.list(followLinks: false)) {
        if (file is! File || !file.path.endsWith('.json')) continue;
        final value = jsonDecode(await file.readAsString()) as Map;
        final hash = value['sourceHash'];
        if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw const FormatException('책 변환 파일 정보를 확인할 수 없습니다.');
        }
        if (ids.any(
          (id) => file.path == '${references.path}/${_hash(id)}.json',
        )) {
          candidates.add(file.path);
          hashes.add(hash);
        } else {
          protectedHashes.add(hash);
        }
      }
    }
    protectedHashes.addAll(
      books
          .where((book) => !ids.contains(book.id))
          .map((book) => book.sourceHash)
          .whereType<String>(),
    );
    for (final hash in hashes.difference(protectedHashes)) {
      final directory = Directory('${references.parent.path}/$hash');
      if (await directory.exists()) {
        await for (final file in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (file is File) candidates.add(file.path);
        }
      }
    }
    for (final id in ids) {
      final legacyHash = HashUtils.fnv1a32(id);
      if (!books.any(
        (book) =>
            !ids.contains(book.id) && HashUtils.fnv1a32(book.id) == legacyHash,
      )) {
        candidates.add('${support.path}/reader_content_cache/$legacyHash.json');
      }
      candidates.add(
        '${support.path}/native_reader_v1/legacy_cache/${_hash(id)}.json',
      );
    }
    return candidates.difference(protected);
  }

  Future<bool> _shared(String path, Set<String> ids, Set<String> owners) async {
    Future<String> identity(String value) async => await File(value).exists()
        ? File(value).resolveSymbolicLinks()
        : File(value).absolute.uri.normalizePath().toFilePath();
    final target = await identity(path);
    final books = await LocalBookRepository(storage).allStoredBooks();
    for (final book in books.where((book) => !ids.contains(book.id))) {
      for (final value in [
        book.localPath,
        book.coverPath,
      ].whereType<String>()) {
        if (await identity(value) == target) return true;
      }
    }
    final covers = await storage.getStringEntriesByPrefix('library_cover_');
    for (final entry in covers.entries) {
      if (!owners.any((id) => _coverKey(id) == entry.key) &&
          RegExp(r'^[a-f0-9]{32}\.png$').hasMatch(entry.value) &&
          await identity('${support.path}/book_covers/${entry.value}') ==
              target) {
        return true;
      }
    }
    final prefix = '${support.path}/native_reader_v1/publications/';
    if (path.startsWith(prefix)) {
      final hash = path.substring(prefix.length).split('/').first;
      if (RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        if (books.any(
          (book) => !ids.contains(book.id) && book.sourceHash == hash,
        )) {
          return true;
        }
        final refs = Directory('${prefix}references');
        if (await refs.exists()) {
          await for (final file in refs.list(followLinks: false)) {
            if (file is File &&
                file.path.endsWith('.json') &&
                !ids.any(
                  (id) => file.path == '${refs.path}/${_hash(id)}.json',
                )) {
              if ((jsonDecode(await file.readAsString())
                      as Map)['sourceHash'] ==
                  hash) {
                return true;
              }
            }
          }
        }
      }
    }
    return false;
  }

  Future<Set<String>> _owners(
    Set<String> ids,
    Map<String, dynamic> entry,
  ) async {
    final owners = {...ids};
    if (entry['group'] is Map) {
      final groupId = entry['group']['id'] as String;
      if (!(await BookGroupRepository(
            storage,
          ).load()).any((g) => g.id == groupId) ||
          (await trash.hiddenGroupIds()).contains(groupId)) {
        owners.add(groupId);
      }
    }
    return owners;
  }

  Future<int> bytes(Set<String> keys) => LibraryMutations.run(() async {
    final data = await trash.load();
    final files = <String>{};
    // Aggregate first so shared files between selected entries count only once.
    final ids = <String>{}, owners = <String>{};
    for (final key in keys) {
      final entry = data[key];
      if (entry == null) continue;
      final bookIds = _bookIds(key, entry);
      ids.addAll(bookIds);
      owners.addAll(await _owners(bookIds, entry));
      files.addAll((entry['purgePaths'] as List? ?? []).cast<String>());
    }
    files.addAll(await _files(ids, owners));
    var result = 0;
    for (final path in files) {
      if (await _owned(path) &&
          !await _shared(path, ids, owners) &&
          await File(path).exists()) {
        result += await File(path).length();
      }
    }
    return result;
  });

  Future<void> purge(String key) => LibraryMutations.run(() async {
    await beforeDelete?.call();
    final data = await trash.load();
    final entry = data[key];
    if (entry == null) return;
    final ids = _bookIds(key, entry);
    final owners = await _owners(ids, entry);
    final paths = await _files(ids, owners);
    // Persist the original plan for retry after partial metadata cleanup.
    if (entry['deleting'] != true) {
      entry['deleting'] = true;
      entry['purgePaths'] = paths.toList();
      await trash.save(data);
    }
    // Retain only paths still unreferenced by other books. Existing plans are
    // retried before metadata is removed, so the same owned paths remain known.
    paths.addAll((entry['purgePaths'] as List? ?? []).cast<String>());
    for (final path in paths) {
      if (await _owned(path) &&
          !await _shared(path, ids, owners) &&
          await File(path).exists()) {
        await File(path).delete();
      }
    }
    await deleteReadingRecords(ids);
    final archiveRaw = await storage.getString(LegacyReaderArchive.backupKey);
    final archive = archiveRaw == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(archiveRaw) as Map);
    for (final id in ids) {
      for (final prefix in [
        AppConstants.readingProgressPrefix,
        AppConstants.readingBookmarkPrefix,
        'library_completion_v1:',
      ]) {
        await storage.remove('$prefix$id');
        archive?.remove('$prefix$id');
      }
    }
    if (archive != null) {
      await storage.setString(
        LegacyReaderArchive.backupKey,
        jsonEncode(archive),
      );
    }
    if (entry['kind'] == 'bundle' && entry['keepShelf'] != true) {
      await BookGroupRepository(
        storage,
      ).finishTrashedGroup(entry['group']['id'] as String);
    }
    await BookGroupRepository(storage).forgetBooks(ids);
    await LocalBookRepository(storage).forgetPermanently(ids);
    for (final id in owners) {
      await storage.remove(_coverKey(id));
    }
    await trash.forget(key);
  });

  Future<void> empty(Set<String> keys) => LibraryMutations.run(() async {
    for (final key in keys) {
      await purge(key);
    }
  });
}
