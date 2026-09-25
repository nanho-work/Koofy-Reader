import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';

class LibraryBackup {
  LibraryBackup(this.manifest, this.files);
  final Map<String, dynamic> manifest;
  final Map<String, Uint8List> files;
  int get bookCount => (manifest['books'] as List).length;
}

/// Portable data only: never copies raw SQLite files, ad rewards, consent or credentials.
class LibraryBackupService {
  LibraryBackupService({
    required this.storage,
    required this.books,
    required this.groups,
    required this.covers,
    required this.reader,
    required this.preparer,
    required this.directory,
  });
  final LocalStorage storage;
  final BookRepository books;
  final BookGroupRepository groups;
  final BookCoverStore covers;
  final NativeReaderStore reader;
  final ReadingPublicationPreparer preparer;
  final Directory directory;
  static const maxBytes = 100 * 1024 * 1024;
  static const coverPrefix = 'library_cover_';

  Future<List<dynamic>> _hiddenBooks() async {
    final raw = await storage.getString(AppConstants.hiddenBooksKey);
    return raw == null || raw.trim().isEmpty ? [] : jsonDecode(raw) as List;
  }

  Future<Uint8List> export({void Function(String)? progress}) async {
    final allBooks = await books.getBooks();
    final allGroups = await groups.load();
    final payload = <String, Uint8List>{};
    final hashes = <String, String>{};
    var total = 0;
    String add(Uint8List bytes, String extension) {
      total += bytes.length;
      if (total > maxBytes) {
        throw const FormatException('한 번에 백업할 수 있는 용량은 100MB입니다.');
      }
      if (payload.length >= 4000) {
        throw const FormatException('백업 파일 항목이 너무 많습니다.');
      }
      final name = 'payload/${payload.length}.$extension';
      payload[name] = bytes;
      hashes[name] = sha256.convert(bytes).toString();
      return name;
    }

    final records = <Map<String, dynamic>>[];
    final coverEntries = <String, String>{};
    for (final book in allBooks) {
      progress?.call('${records.length + 1}/${allBooks.length}권 백업 준비 중');
      final json = book.toJson()
        ..remove('localPath')
        ..remove('coverPath');
      if (book.isLocalFile) {
        try {
          final source = await preparer.backupSource(book);
          json['source'] = add(source.bytes, source.extension);
        } catch (error) {
          throw FormatException(
            '“${book.title}”을 백업하지 못했습니다. 원본 파일과 저장 공간을 확인해 주세요. ($error)',
          );
        }
      }
      records.add(json);
    }
    final groupBooks = await covers.apply(
      allGroups.map((g) => g.displayBook).toList(),
    );
    for (final book in [...allBooks, ...groupBooks]) {
      final path = book.coverPath;
      if (path == null) continue;
      final file = File(path);
      if (!await file.exists()) {
        continue; // A missing cover is already rendered as a title cover.
      }
      if (await file.length() > BookCoverStore.maxBytes) {
        throw const FormatException('표지 이미지가 너무 큽니다.');
      }
      coverEntries[book.id] = add(await file.readAsBytes(), 'png');
    }
    final ids = {...allBooks.map((b) => b.id), 'sample_1', 'sample_2'};
    final manifest = <String, dynamic>{
      'format': 'koofy-reader-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'books': records,
      'groups': allGroups.map((g) => g.toJson()).toList(),
      'covers': coverEntries,
      'files': hashes,
      'reader': await reader.exportBackup(ids),
      'completion': await LibraryCompletionRepository(storage).load(),
      'hidden': await _hiddenBooks(),
    };
    final encoded = utf8.encode(jsonEncode(manifest));
    if (encoded.length > 5 * 1024 * 1024 || total + encoded.length > maxBytes) {
      throw const FormatException('백업 정보가 100MB 제한을 초과했습니다.');
    }
    return Isolate.run(() {
      final archive = Archive()
        ..addFile(ArchiveFile('manifest.json', encoded.length, encoded));
      for (final entry in payload.entries) {
        archive.addFile(
          ArchiveFile(entry.key, entry.value.length, entry.value),
        );
      }
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      if (bytes.length > maxBytes) {
        throw const FormatException('백업 파일이 100MB를 초과합니다.');
      }
      return bytes;
    });
  }

  static Future<LibraryBackup> read(File file) async {
    if (await file.length() > maxBytes) {
      throw const FormatException('100MB 이하의 백업 파일을 선택해 주세요.');
    }
    final bytes = await file.readAsBytes();
    return Isolate.run(() => decode(bytes));
  }

  static LibraryBackup decode(Uint8List bytes) {
    if (bytes.length > maxBytes) throw const FormatException('백업 파일이 너무 큽니다.');
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > 4001) {
      throw const FormatException('백업 파일 항목이 너무 많습니다.');
    }
    var total = 0;
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile ||
          file.isSymbolicLink ||
          (file.name != 'manifest.json' &&
              !RegExp(
                r'^payload/[0-9]+\.(txt|epub|png)$',
              ).hasMatch(file.name)) ||
          files.containsKey(file.name)) {
        throw const FormatException('올바르지 않은 백업 파일 경로입니다.');
      }
      total += file.size;
      if (file.size < 0 || total > maxBytes) {
        throw const FormatException('백업 해제 용량이 100MB를 초과합니다.');
      }
      final content = Uint8List.fromList(file.content);
      if (content.length != file.size) {
        throw const FormatException('백업 파일 크기가 일치하지 않습니다.');
      }
      files[file.name] = content;
    }
    final raw = files.remove('manifest.json');
    if (raw == null || raw.length > 5 * 1024 * 1024) {
      throw const FormatException('쿠피리더 백업 정보가 없습니다.');
    }
    final manifest = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(raw)) as Map,
    );
    if (manifest['format'] != 'koofy-reader-backup' ||
        manifest['version'] != 1) {
      throw const FormatException('지원하지 않는 백업 형식입니다.');
    }
    final hashes = Map<String, dynamic>.from(manifest['files'] as Map);
    if (hashes.length != files.length) {
      throw const FormatException('백업 파일이 누락되었습니다.');
    }
    for (final entry in files.entries) {
      if (hashes[entry.key] != sha256.convert(entry.value).toString()) {
        throw const FormatException('손상된 백업 파일입니다. 원래 백업을 다시 선택해 주세요.');
      }
    }
    final ids = <String>{'sample_1', 'sample_2'};
    final bookIds = <String>{};
    for (final raw in manifest['books'] as List) {
      final json = Map<String, dynamic>.from(raw as Map);
      final book = Book.fromJson(json);
      if (book == null ||
          book.id.length > 200 ||
          !bookIds.add(book.id) ||
          (json['sourceType'] != 'asset' &&
              json['sourceType'] != 'localFile')) {
        throw const FormatException('책 정보가 올바르지 않습니다.');
      }
      ids.add(book.id);
      if (book.isLocalFile) {
        final name = json['source'];
        if (name is! String ||
            !(name.endsWith('.txt') || name.endsWith('.epub')) ||
            !files.containsKey(name) ||
            files[name]!.length >
                (name.endsWith('.txt')
                    ? AppConstants.maxTxtBytes
                    : AppConstants.maxEpubBytes)) {
          throw const FormatException('책 원본이 누락되거나 지원 용량을 초과했습니다.');
        }
      } else if (!const ['sample_1', 'sample_2'].contains(book.id) ||
          book.assetPath != 'assets/books/${book.id}.txt') {
        throw const FormatException('지원하지 않는 기본 책입니다.');
      }
    }
    final groupIds = <String>{};
    final members = <String>{};
    for (final raw in manifest['groups'] as List) {
      final group = BookGroup.fromJson(Map<String, dynamic>.from(raw as Map));
      if (!groupIds.add(group.id) ||
          group.id.length > 200 ||
          group.bookIds.any((id) => !members.add(id))) {
        throw const FormatException('중복된 묶음 정보입니다.');
      }
    }
    final coverEntries = Map<String, dynamic>.from(manifest['covers'] as Map);
    for (final entry in coverEntries.entries) {
      if ((!ids.contains(entry.key) && !groupIds.contains(entry.key)) ||
          entry.value is! String ||
          !entry.value.toString().endsWith('.png') ||
          !files.containsKey(entry.value) ||
          files[entry.value]!.length > BookCoverStore.maxBytes) {
        throw const FormatException('표지 정보가 올바르지 않습니다.');
      }
    }
    final state = Map<String, dynamic>.from(manifest['reader'] as Map);
    preferencesFromJson(state['preferences'] as String);
    final positions = <String>{};
    for (final raw in state['positions'] as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final id = row['bookId'];
      final revision = row['revision'];
      if (id is! String ||
          revision is! String ||
          revision.isEmpty ||
          !ids.contains(id) ||
          !positions.add(jsonEncode([id, revision])) ||
          (row['openedAt'] != null && row['openedAt'] is! int)) {
        throw const FormatException('독서 기록이 올바르지 않습니다.');
      }
      validateBookmarksJson(row['bookmarks'] as String? ?? '[]');
      final locator = row['locator'];
      if (locator != null) {
        final data = jsonDecode(locator as String);
        if (data is! Map ||
            data['href'] is! String ||
            (data['href'] as String).isEmpty) {
          throw const FormatException('독서 위치가 올바르지 않습니다.');
        }
      }
    }
    if ((manifest['hidden'] as List).any((id) => id is! String) ||
        (manifest['completion'] as Map).values.any((v) => v is! bool)) {
      throw const FormatException('서재 상태가 올바르지 않습니다.');
    }
    return LibraryBackup(manifest, files);
  }

  Future<int> restore(LibraryBackup backup) async {
    final manifest = backup.manifest;
    final current = await books.getBooks();
    final currentIds = current.map((b) => b.id).toSet();
    final rawLocal = await storage.getString(AppConstants.localBooksKey);
    final local = rawLocal == null || rawLocal.isEmpty
        ? <dynamic>[]
        : jsonDecode(rawLocal) as List;
    // Hidden samples are still installed, so never introduce duplicate sample entries.
    currentIds.addAll(['sample_1', 'sample_2']);
    final restored = <String>{};
    final pending = <String, String>{};
    await directory.create(recursive: true);
    final stage = await directory.createTemp('restore-');
    try {
      for (final raw in manifest['books'] as List) {
        final json = Map<String, dynamic>.from(raw as Map);
        final id = json['id'] as String;
        if (currentIds.contains(id)) continue;
        final source = json['source'] as String;
        final file = File('${stage.path}/${source.split('/').last}');
        await file.writeAsBytes(backup.files[source]!, flush: true);
        json['localPath'] = file.path;
        json.remove('coverPath');
        json.remove('source');
        local.add(json);
        restored.add(id);
      }
      pending[AppConstants.localBooksKey] = jsonEncode(local);
      pending[AppConstants.localBooksBackupKey] = jsonEncode(local);
      final allIds = {...currentIds, ...restored};
      final existingGroups = await groups.load();
      final groupIds = existingGroups.map((g) => g.id).toSet();
      final memberIds = existingGroups.expand((g) => g.bookIds).toSet();
      final restoredGroups = <String>{};
      for (final raw in manifest['groups'] as List) {
        final group = BookGroup.fromJson(Map<String, dynamic>.from(raw as Map));
        if (groupIds.contains(group.id)) continue;
        final ids = group.bookIds
            .where((id) => allIds.contains(id) && !memberIds.contains(id))
            .toList();
        if (ids.isEmpty) continue;
        existingGroups.add(group.copyWith(bookIds: ids));
        memberIds.addAll(ids);
        restoredGroups.add(group.id);
      }
      pending[BookGroupRepository.storageKey] = jsonEncode({
        'revision': stage.path,
        'groups': existingGroups.map((g) => g.toJson()).toList(),
      });
      final oldCovers = await storage.getStringEntriesByPrefix(coverPrefix);
      final coverDir = Directory('${directory.parent.path}/book_covers');
      await coverDir.create(recursive: true);
      for (final entry in (manifest['covers'] as Map).entries) {
        final id = entry.key as String;
        final key = '$coverPrefix${base64Url.encode(utf8.encode(id))}';
        if (oldCovers.containsKey(key) ||
            (!allIds.contains(id) && !restoredGroups.contains(id))) {
          continue;
        }
        final bytes = backup.files[entry.value]!;
        final name = '${md5.convert(bytes)}.png';
        await File('${coverDir.path}/$name').writeAsBytes(bytes, flush: true);
        pending[key] = name;
      }
      for (final entry in (manifest['completion'] as Map).entries) {
        final key = '${LibraryCompletionRepository.prefix}${entry.key}';
        if (allIds.contains(entry.key) &&
            await storage.getString(key) == null) {
          pending[key] = '${entry.value}';
        }
      }
      final hidden = await _hiddenBooks();
      pending[AppConstants.hiddenBooksKey] = jsonEncode(
        {...hidden, ...manifest['hidden'] as List}.toList(),
      );
      final previous = <String, String?>{};
      for (final key in pending.keys) {
        previous[key] = await storage.getString(key);
      }
      final written = <String>[];
      try {
        await reader.mergeBackup(
          Map<String, dynamic>.from(manifest['reader'] as Map),
          allIds,
          () async {
            for (final entry in pending.entries) {
              written.add(entry.key);
              await storage.setString(entry.key, entry.value);
            }
          },
        );
      } catch (_) {
        for (final key in written.reversed) {
          await storage.setString(key, previous[key] ?? '');
        }
        rethrow;
      }
      return restored.length;
    } catch (_) {
      // Keep staged files on failure: if a device is out of space even rollback
      // may fail. Never delete a file that a partially committed index references.
      rethrow;
    }
  }
}
