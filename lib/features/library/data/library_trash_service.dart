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
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';

enum TrashDeleteStage { preparing, files, records }

class TrashDeleteProgress {
  const TrashDeleteProgress({
    required this.stage,
    required this.completedEntries,
    required this.totalEntries,
    this.title = '',
    this.currentEntries = 1,
    this.completedFiles = 0,
    this.totalFiles = 0,
  });
  final TrashDeleteStage stage;
  final int completedEntries, totalEntries, completedFiles, totalFiles;
  final String title;
  final int currentEntries;
}

final libraryTrashProgressProvider = StateProvider<TrashDeleteProgress?>(
  (ref) => null,
);

final libraryTrashServiceProvider = FutureProvider<LibraryTrashService>((
  ref,
) async {
  final native = await ref.watch(nativeReaderServicesProvider.future);
  return LibraryTrashService(
    ref.watch(localStorageProvider),
    native.supportDirectory!,
    onProgress: (progress) =>
        ref.read(libraryTrashProgressProvider.notifier).state = progress,
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
    this.onProgress,
  });
  final LocalStorage storage;
  final Directory support;
  final Future<void> Function(Set<String>) deleteReadingRecords;
  final Future<void> Function()? beforeDelete;
  final void Function(TrashDeleteProgress?)? onProgress;
  bool _running = false;
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

  Future<Set<String>> _files(
    Set<String> ids,
    Set<String> ownerIds,
    _TrashSnapshot snapshot,
  ) async {
    final books = snapshot.books;
    final covers = snapshot.covers;
    final candidates = <String>{};
    final protected = <String>{};
    for (final book in books) {
      final paths = [book.localPath, book.coverPath].whereType<String>();
      (ids.contains(book.id) ? candidates : protected).addAll(paths);
    }
    for (final cover in covers.entries) {
      if (!RegExp(r'^[a-f0-9]{32}\.png$').hasMatch(cover.value)) continue;
      (ownerIds.map(_coverKey).contains(cover.key) ? candidates : protected)
          .add('${support.path}/book_covers/${cover.value}');
    }
    final references = Directory(
      '${support.path}/native_reader_v1/publications/references',
    );
    final hashes = <String>{}, protectedHashes = <String>{};
    final referenceNames = ids.map(_hash).toSet();
    for (final reference in snapshot.references.entries) {
      if (referenceNames.contains(reference.key)) {
        candidates.add('${references.path}/${reference.key}.json');
        hashes.add(reference.value);
      } else {
        protectedHashes.add(reference.value);
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

  Future<_TrashProtection> _protection(
    Set<String> ids,
    Set<String> owners,
    _TrashSnapshot snapshot,
  ) async {
    final paths = <String>{}, hashes = <String>{};
    final books = snapshot.books;
    for (final book in books.where((book) => !ids.contains(book.id))) {
      if (book.sourceHash != null) hashes.add(book.sourceHash!);
      for (final value in [
        book.localPath,
        book.coverPath,
      ].whereType<String>()) {
        paths.add(await snapshot.identity(value));
      }
    }
    final covers = snapshot.covers;
    final coverKeys = owners.map(_coverKey).toSet();
    for (final entry in covers.entries) {
      if (!coverKeys.contains(entry.key) &&
          RegExp(r'^[a-f0-9]{32}\.png$').hasMatch(entry.value)) {
        paths.add(
          await snapshot.identity('${support.path}/book_covers/${entry.value}'),
        );
      }
    }
    final selectedReferences = ids.map(_hash).toSet();
    for (final reference in snapshot.references.entries) {
      if (!selectedReferences.contains(reference.key)) {
        hashes.add(reference.value);
      }
    }
    return _TrashProtection(paths, hashes);
  }

  Future<Set<String>> _owners(
    Set<String> ids,
    Map<String, dynamic> entry,
    _TrashSnapshot snapshot,
  ) async {
    final owners = {...ids};
    if (entry['group'] is Map) {
      final groupId = entry['group']['id'] as String;
      if (!snapshot.groupIds.contains(groupId) ||
          snapshot.hiddenGroupIds.contains(groupId)) {
        owners.add(groupId);
      }
    }
    return owners;
  }

  Future<int> bytes(Set<String> keys) => LibraryMutations.run(() async {
    final data = await trash.load();
    final snapshot = await _snapshot(data);
    final files = <String>{};
    // Aggregate first so shared files between selected entries count only once.
    final ids = <String>{}, owners = <String>{};
    for (final key in keys) {
      final entry = data[key];
      if (entry == null) continue;
      final bookIds = _bookIds(key, entry);
      ids.addAll(bookIds);
      owners.addAll(await _owners(bookIds, entry, snapshot));
      files.addAll((entry['purgePaths'] as List? ?? []).cast<String>());
    }
    files.addAll(await _files(ids, owners, snapshot));
    final protection = await _protection(ids, owners, snapshot);
    var result = 0;
    for (final path in files) {
      if (await _owned(path) &&
          !await _shared(path, protection, snapshot) &&
          await File(path).exists()) {
        result += await File(path).length();
      }
    }
    return result;
  });

  Future<void> purge(String key) => empty({key});

  Future<void> _purge(
    List<String> keys,
    Map<String, Map<String, dynamic>> data,
    _TrashSnapshot snapshot,
    int completed,
    int total,
  ) async {
    final selected = {
      for (final key in keys)
        if (data.containsKey(key)) key: data[key]!,
    };
    if (selected.isEmpty) return;
    final ids = <String>{}, owners = <String>{}, paths = <String>{};
    for (final item in selected.entries) {
      final bookIds = _bookIds(item.key, item.value);
      ids.addAll(bookIds);
      owners.addAll(await _owners(bookIds, item.value, snapshot));
      paths.addAll((item.value['purgePaths'] as List? ?? []).cast<String>());
    }
    paths.addAll(await _files(ids, owners, snapshot));
    // Small batches amortize metadata writes. Every affected entry owns a durable
    // retry plan BEFORE any file is removed, even if only one entry is retried.
    // Shared-file protection is recalculated for that retry's selected IDs.
    final plan = paths.toList();
    for (final entry in selected.values) {
      entry['deleting'] = true;
      entry['purgePaths'] = plan;
    }
    await trash.save(data);
    final protection = await _protection(ids, owners, snapshot);
    var done = 0;
    void report(TrashDeleteStage stage) => onProgress?.call(
      TrashDeleteProgress(
        stage: stage,
        title: selected.values.first['title'] as String,
        currentEntries: selected.length,
        completedEntries: completed,
        totalEntries: total,
        completedFiles: done,
        totalFiles: paths.length,
      ),
    );
    report(TrashDeleteStage.files);
    for (final path in paths) {
      if (await _owned(path) &&
          !await _shared(path, protection, snapshot) &&
          await File(path).exists()) {
        await File(path).delete();
      }
      done++;
      report(TrashDeleteStage.files);
    }
    report(TrashDeleteStage.records);
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
        if (snapshot.legacyKeys.remove('$prefix$id')) {
          await storage.remove('$prefix$id');
        }
        archive?.remove('$prefix$id');
      }
    }
    if (archive != null) {
      await storage.setString(
        LegacyReaderArchive.backupKey,
        jsonEncode(archive),
      );
    }
    for (final entry in selected.values) {
      if (entry['kind'] == 'bundle' && entry['keepShelf'] != true) {
        await BookGroupRepository(
          storage,
        ).finishTrashedGroup(entry['group']['id'] as String);
      }
    }
    await BookGroupRepository(storage).forgetBooks(ids);
    await LocalBookRepository(storage).forgetPermanently(ids);
    for (final id in owners) {
      if (snapshot.covers.containsKey(_coverKey(id))) {
        await storage.remove(_coverKey(id));
      }
    }
    for (final key in selected.keys) {
      data.remove(key);
    }
    await trash.save(data);
    snapshot.books.removeWhere((book) => ids.contains(book.id));
    snapshot.covers.removeWhere(
      (key, _) => owners.map(_coverKey).contains(key),
    );
    for (final id in ids) {
      snapshot.references.remove(_hash(id));
    }
    for (final entry in selected.values) {
      if (entry['kind'] == 'bundle' && entry['keepShelf'] != true) {
        snapshot.groupIds.remove(entry['group']['id']);
      }
    }
    onProgress?.call(
      TrashDeleteProgress(
        stage: TrashDeleteStage.preparing,
        completedEntries: completed + selected.length,
        totalEntries: total,
      ),
    );
  }

  Future<void> empty(Set<String> keys) async {
    if (_running) throw StateError('삭제 작업이 진행 중입니다.');
    if (keys.isEmpty) return;
    _running = true;
    onProgress?.call(
      TrashDeleteProgress(
        stage: TrashDeleteStage.preparing,
        completedEntries: 0,
        totalEntries: keys.length,
      ),
    );
    try {
      await LibraryMutations.run(() async {
        await beforeDelete?.call();
        final data = await trash.load();
        final selected = keys.where(data.containsKey).toList();
        final snapshot = await _snapshot(data);
        for (var i = 0; i < selected.length; i += 16) {
          await _purge(
            selected.skip(i).take(16).toList(),
            data,
            snapshot,
            i,
            selected.length,
          );
        }
      });
    } finally {
      _running = false;
      onProgress?.call(null);
    }
  }

  Future<bool> _shared(
    String path,
    _TrashProtection protection,
    _TrashSnapshot snapshot,
  ) async {
    if (protection.paths.contains(await snapshot.identity(path))) return true;
    final prefix = '${support.path}/native_reader_v1/publications/';
    return path.startsWith(prefix) &&
        protection.hashes.contains(
          path.substring(prefix.length).split('/').first,
        );
  }

  Future<_TrashSnapshot> _snapshot(
    Map<String, Map<String, dynamic>> data,
  ) async {
    final books = await LocalBookRepository(storage).allStoredBooks();
    final covers = await storage.getStringEntriesByPrefix('library_cover_');
    final references = <String, String>{};
    final directory = Directory(
      '${support.path}/native_reader_v1/publications/references',
    );
    if (await directory.exists()) {
      await for (final file in directory.list(followLinks: false)) {
        if (file is! File || !file.path.endsWith('.json')) continue;
        final value = jsonDecode(await file.readAsString()) as Map;
        final hash = value['sourceHash'];
        if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw const FormatException('책 변환 파일 정보를 확인할 수 없습니다.');
        }
        references[file.uri.pathSegments.last.replaceFirst(
              RegExp(r'\.json$'),
              '',
            )] =
            hash;
      }
    }
    final legacyKeys = <String>{};
    for (final prefix in [
      AppConstants.readingProgressPrefix,
      AppConstants.readingBookmarkPrefix,
      'library_completion_v1:',
    ]) {
      legacyKeys.addAll((await storage.getStringEntriesByPrefix(prefix)).keys);
    }
    return _TrashSnapshot(
      books,
      Map.of(covers),
      references,
      (await BookGroupRepository(storage).load()).map((g) => g.id).toSet(),
      {
        for (final entry in data.values)
          if (entry['kind'] == 'bundle' && entry['keepShelf'] != true)
            entry['group']['id'] as String,
      },
      legacyKeys,
    );
  }
}

/// Valid only while the library mutation lease is held. Reuse disk identities and
/// indexes across an entire batch; never cache this across independent operations.
class _TrashSnapshot {
  _TrashSnapshot(
    this.books,
    this.covers,
    this.references,
    this.groupIds,
    this.hiddenGroupIds,
    this.legacyKeys,
  );
  final List<Book> books;
  final Map<String, String> covers, references;
  final Set<String> groupIds, hiddenGroupIds, legacyKeys;
  final _identities = <String, String>{};

  Future<String> identity(String path) async {
    final cached = _identities[path];
    if (cached != null) return cached;
    return _identities[path] = await File(path).exists()
        ? await File(path).resolveSymbolicLinks()
        : File(path).absolute.uri.normalizePath().toFilePath();
  }
}

class _TrashProtection {
  const _TrashProtection(this.paths, this.hashes);
  final Set<String> paths, hashes;
}
