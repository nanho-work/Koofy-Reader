import 'package:koofy_reader/features/library/domain/bundled_books.dart';
import 'package:koofy_reader/features/fonts/data/personal_fonts.dart';
import 'speech_backup.dart';
import 'package:koofy_reader/features/settings/data/reader_cover_settings.dart';
import 'dart:convert';
import 'package:koofy_reader/core/storage/library_mutations.dart';
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
    this.speech,
  });
  final SpeechBackup? speech;
  final LocalStorage storage;
  final BookRepository books;
  final BookGroupRepository groups;
  final BookCoverStore covers;
  final NativeReaderStore reader;
  final ReadingPublicationPreparer preparer;
  final Directory directory;
  static const maxBytes = 100 * 1024 * 1024;
  PersonalFontStore get personalFonts =>
      PersonalFontStore(Directory('${directory.parent.path}/personal_fonts'));
  static const coverPrefix = 'library_cover_';

  Future<List<dynamic>> _hiddenBooks() async {
    final raw = await storage.getString(AppConstants.hiddenBooksKey);
    return raw == null || raw.trim().isEmpty ? [] : jsonDecode(raw) as List;
  }

  Future<Uint8List> export({
    void Function(String)? progress,
  }) => LibraryMutations.run(() async {
    final allBooks = await books.getBooks();
    final activeIds = allBooks.map((b) => b.id).toSet();
    final allGroups = (await groups.load())
        .map(
          (g) =>
              g.copyWith(bookIds: g.bookIds.where(activeIds.contains).toList()),
        )
        .where((g) => g.bookIds.isNotEmpty)
        .toList();
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
        ..remove('importSourcePath')
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
    final ids = {...allBooks.map((b) => b.id), ...BundledBooks.ids};
    final fontEntries = <Map<String, dynamic>>[];
    for (final family in await personalFonts.load()) {
      final bytes = await personalFonts.fileFor(family).readAsBytes();
      final extension = PersonalFontStore.validate(bytes);
      fontEntries.add({
        'id': family['id'],
        'label': family['label'],
        'source': add(bytes, extension),
      });
    }
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
      'displayCover': await storage.getInt(readerCoverSettingKey) != 0,
      'personalFonts': fontEntries,
      'speech': SpeechBackup.validated(await speech?.export(), ids),
    };
    final encoded = utf8.encode(jsonEncode(manifest));
    if (encoded.length > 5 * 1024 * 1024 || total + encoded.length > maxBytes) {
      throw const FormatException('백업 정보가 100MB 제한을 초과했습니다.');
    }
    return _encodeArchive(encoded, payload);
  });

  static Future<Uint8List> _encodeArchive(
    List<int> encoded,
    Map<String, Uint8List> payload,
  ) => Isolate.run(() {
    final archive = Archive()
      ..addFile(ArchiveFile('manifest.json', encoded.length, encoded));
    for (final entry in payload.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    if (bytes.length > maxBytes) {
      throw const FormatException('백업 파일이 100MB를 초과합니다.');
    }
    return bytes;
  });

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
                r'^payload/[0-9]+\.(txt|epub|png|otf|ttf)$',
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
    final ids = <String>{...BundledBooks.ids};
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
      } else if (!BundledBooks.isSupported(book)) {
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
    if (manifest['displayCover'] != null && manifest['displayCover'] is! bool) {
      throw const FormatException('표지 표시 설정이 올바르지 않습니다.');
    }
    final fontEntries = manifest['personalFonts'] ?? [];
    if (fontEntries is! List ||
        fontEntries.length > PersonalFontStore.maxFonts) {
      throw const FormatException('개인 글꼴 백업이 올바르지 않습니다.');
    }
    final fontIds = <String>{};
    for (final raw in fontEntries) {
      if (raw is! Map ||
          raw['source'] is! String ||
          raw['label'] is! String ||
          (raw['label'] as String).length > 120) {
        throw const FormatException('글꼴 백업 정보가 올바르지 않습니다.');
      }
      final bytes = files[raw['source']];
      if (bytes == null) throw const FormatException('글꼴 파일이 누락되었습니다.');
      PersonalFontStore.validate(bytes);
      final id =
          'personal_${sha256.convert(bytes).toString().substring(0, 32)}';
      if (raw['id'] != id || !fontIds.add(id)) {
        throw const FormatException('글꼴 식별자가 올바르지 않습니다.');
      }
    }
    manifest['speech'] = SpeechBackup.validated(manifest['speech'], ids);
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

  Future<int> restore(LibraryBackup backup) => LibraryMutations.run(() async {
    final manifest = backup.manifest;
    // Install immutable font files before committing preferences that refer to them.
    // Existing fonts are retained; retrying a partially completed restore is idempotent.
    for (final raw in manifest['personalFonts'] as List? ?? []) {
      await personalFonts.install(
        backup.files[raw['source']]!,
        raw['label'] as String,
      );
    }
    final restoredReader = Map<String, dynamic>.from(manifest['reader'] as Map);
    final prefs = preferencesFromJson(restoredReader['preferences'] as String);
    if (prefs.fontId?.startsWith('personal_') == true &&
        !(await personalFonts.load()).any((f) => f['id'] == prefs.fontId)) {
      prefs.fontId = 'default';
      restoredReader['preferences'] = preferencesToJson(prefs);
    }
    final current = await books.getBooks();
    final currentIds = current.map((b) => b.id).toSet();
    final rawLocal = await storage.getString(AppConstants.localBooksKey);
    final local = rawLocal == null || rawLocal.isEmpty
        ? <dynamic>[]
        : jsonDecode(rawLocal) as List;
    // Trashed books are retained in the index; do not duplicate or unhide them on restore.
    currentIds.addAll(local.map((raw) => (raw as Map)['id'] as String));
    // Hidden samples are still installed, so never introduce duplicate sample entries.
    currentIds.addAll(BundledBooks.ids);
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
        json['sourceHash'] = await _sourceHash(backup.files[source]!);
        json.remove('coverPath');
        json.remove('importSourcePath');
        json.remove('source');
        local.add(json);
        restored.add(id);
      }
      if ((manifest['books'] as List).any(
        (raw) => raw['id'] == BundledBooks.legacy.id,
      )) {
        pending[BundledBooks.retainLegacyKey] = 'true';
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
        final name = '${md5.convert(utf8.encode('${stage.path}:$id'))}.png';
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
      final oldCover = await storage.getInt(readerCoverSettingKey);
      final restoreCover = oldCover == null && manifest['displayCover'] is bool;
      var coverWritten = false;
      try {
        await reader.mergeBackup(restoredReader, allIds, () async {
          for (final entry in pending.entries) {
            written.add(entry.key);
            await storage.setString(entry.key, entry.value);
          }
          if (restoreCover) {
            coverWritten = true;
            await storage.setInt(
              readerCoverSettingKey,
              manifest['displayCover'] == true ? 1 : 0,
            );
          }
          final listening = SpeechBackup.validated(manifest['speech'], allIds);
          if (listening.isNotEmpty) await speech?.merge(listening);
        });
      } catch (_) {
        if (coverWritten) await storage.remove(readerCoverSettingKey);
        for (final key in written.reversed) {
          final value = previous[key];
          if (value == null) {
            await storage.remove(key);
          } else {
            await storage.setString(key, value);
          }
        }
        rethrow;
      }
      return restored.length;
    } catch (_) {
      // Keep staged files on failure: if a device is out of space even rollback
      // may fail. Never delete a file that a partially committed index references.
      rethrow;
    }
  });
}

Future<String> _sourceHash(Uint8List bytes) =>
    Isolate.run(() => sha256.convert(bytes).toString());
