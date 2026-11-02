import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_order.dart';
import 'book_import.dart';
import 'cover_matching.dart';

const importJournalKey = 'library_import_job_v1';
final bookImportControllerProvider =
    ChangeNotifierProvider<BookImportController>((ref) {
      return BookImportController(
        ref.read(localStorageProvider),
        ref.read(bookRepositoryProvider),
        ref.read(bookGroupRepositoryProvider),
        changed: () {
          ref.invalidate(booksProvider);
          ref.invalidate(bookGroupsProvider);
        },
      );
    });

class ImportSource {
  ImportSource(
    this.name,
    this.source, {
    this.path,
    this.bookId,
    this.done = false,
    this.error = false,
  });
  final String name, source;
  String? path, bookId;
  bool done, error;
  bool get image => coverImageExtensions.contains(fileExtension(name));
  Map<String, dynamic> toJson() => {
    'name': name,
    'source': source,
    'path': path,
    'bookId': bookId,
    'done': done,
    'error': error,
  };
  factory ImportSource.fromJson(Map<String, dynamic> value) => ImportSource(
    value['name'] as String,
    value['source'] as String,
    path: value['path'] as String?,
    bookId: value['bookId'] as String?,
    done: value['done'] == true,
    error: value['error'] == true,
  );
}

enum ImportStage {
  idle,
  selecting,
  review,
  receiving,
  registering,
  covers,
  grouping,
  finished,
}

/// One application-owned job, independent of the screen that started it. The
/// journal checkpoints only committed book chunks; retry never trusts UI counts.
class BookImportController extends ChangeNotifier {
  BookImportController(
    this.storage,
    this.repository,
    this.groups, {
    required this.changed,
    Future<Directory> Function()? temporaryDirectory,
    this.copyTimeout = const Duration(seconds: 90),
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory {
    ready = _restore();
    channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && busy) {
        bytes = (call.arguments as Map)['bytes'] as int;
        notifyListeners();
      }
    });
  }
  final LocalStorage storage;
  final BookRepository repository;
  final BookGroupRepository groups;
  final VoidCallback changed;
  final Duration copyTimeout;
  final Future<Directory> Function() _temporaryDirectory;
  final MethodChannel channel = const MethodChannel('koofy_reader/book_import');
  late final Future<void> ready;
  List<ImportSource> files = [];
  ImportStage stage = ImportStage.idle;
  String current = '', message = '', group = '', groupTitle = '';
  String? createdGroupId;
  bool applyCovers = true, stopRequested = false, interrupted = false;
  int bytes = 0;
  bool get busy => const [
    ImportStage.selecting,
    ImportStage.receiving,
    ImportStage.registering,
    ImportStage.covers,
    ImportStage.grouping,
  ].contains(stage);
  List<ImportSource> get books => files.where((f) => !f.image).toList();
  int get completed => books.where((f) => f.done).length;
  int get failures => files.where((f) => f.error).length;

  Future<void> _restore() async {
    try {
      final raw = await storage.getString(importJournalKey);
      if (raw == null) return;
      final value = jsonDecode(raw) as Map<String, dynamic>;
      if (value['version'] != 1) throw const FormatException('import version');
      files = (value['files'] as List)
          .map(
            (f) => ImportSource.fromJson(Map<String, dynamic>.from(f as Map)),
          )
          .toList();
      group = value['group'] as String? ?? '';
      groupTitle = value['groupTitle'] as String? ?? '';
      createdGroupId = value['createdGroupId'] as String?;
      applyCovers = value['applyCovers'] != false;
      interrupted = files.isNotEmpty;
      stage = files.isEmpty ? ImportStage.idle : ImportStage.review;
    } catch (_) {
      message = '가져오기 기록을 읽지 못했습니다. 파일을 다시 선택해 주세요.';
    }
    notifyListeners();
  }

  Future<void> checkpoint() => storage.setString(
    importJournalKey,
    jsonEncode({
      'version': 1,
      'files': files.map((f) => f.toJson()).toList(),
      'group': group,
      'groupTitle': groupTitle,
      'createdGroupId': createdGroupId,
      'applyCovers': applyCovers,
    }),
  );
  void optionsChanged() {
    notifyListeners();
  }

  Future<void> pick() async {
    await ready;
    if (busy) return;
    stage = ImportStage.selecting;
    message = '';
    notifyListeners();
    try {
      final selected = await channel.invokeListMethod<dynamic>('pick') ?? [];
      files = selected.map((f) {
        final m = Map<String, dynamic>.from(f as Map);
        return ImportSource(m['name'] as String, m['source'] as String);
      }).toList()..sort((a, b) => compareBookTitles(a.name, b.name));
      if (files.isNotEmpty) await checkpoint();
    } catch (_) {
      message = '파일을 선택하지 못했습니다. 다시 시도해 주세요.';
    }
    stage = files.isEmpty ? ImportStage.idle : ImportStage.review;
    notifyListeners();
  }

  Future<String> prepare(ImportSource file) async {
    current = file.name;
    bytes = 0;
    stage = ImportStage.receiving;
    notifyListeners();
    if (file.path != null && await File(file.path!).exists()) return file.path!;
    String? path;
    try {
      path = await channel
          .invokeMethod<String>('copy', {
            'name': file.name,
            'source': file.source,
            'limit': fileExtension(file.name) == 'epub'
                ? 40 * 1024 * 1024
                : 20 * 1024 * 1024,
          })
          .timeout(
            copyTimeout,
            onTimeout: () async {
              stopRequested = true;
              message = '파일 응답이 늦어 가져오기를 멈췄습니다. 연결을 확인하고 다시 시도해 주세요.';
              notifyListeners();
              await channel.invokeMethod<void>('cancel');
              throw TimeoutException('file provider timeout');
            },
          );
    } on PlatformException catch (error) {
      if (error.code == 'busy') {
        stopRequested = true;
        message = '이전 파일 작업을 정리하는 중입니다. 잠시 후 다시 시도해 주세요.';
        notifyListeners();
      }
      rethrow;
    }
    if (path == null) throw const FileSystemException('file unavailable');
    file.path = path;
    return path;
  }

  Future<void> stop() async {
    if (!busy || stage == ImportStage.selecting) return;
    stopRequested = true;
    notifyListeners();
    if (stage == ImportStage.receiving) {
      await channel.invokeMethod<void>('cancel');
    }
  }

  Future<void> run({Future<Book?> Function(String)? importFile}) async {
    await ready;
    if (busy ||
        files.isEmpty ||
        (group == 'new' && groupTitle.trim().isEmpty)) {
      return;
    }
    stopRequested = false;
    message = '';
    interrupted = false;
    stage = ImportStage.receiving;
    notifyListeners();
    try {
      if (group == 'new') {
        createdGroupId ??=
            'group_import_${DateTime.now().microsecondsSinceEpoch}';
      }
      await checkpoint();
      final pending = books.where((f) => !f.done).toList();
      for (
        var offset = 0;
        offset < pending.length && !stopRequested;
        offset += 16
      ) {
        final prepared = <ImportSource>[];
        for (final file in pending.skip(offset).take(16)) {
          if (stopRequested) break;
          file.error = false;
          try {
            await prepare(file);
            prepared.add(file);
          } catch (_) {
            if (!stopRequested) file.error = true;
          }
        }
        if (stopRequested) {
          await checkpoint();
          break;
        }
        final accepted = <ImportSource>[];
        stage = ImportStage.registering;
        notifyListeners();
        await importBooks(
          repository,
          prepared.map((f) => BookImportFile(f.name, f.path)).toList(),
          importFile: (path) async {
            final source = prepared.firstWhere((f) => f.path == path);
            current = source.name;
            notifyListeners();
            final book = await (importFile ?? repository.importBookFile)(path);
            if (book != null) {
              source.bookId = book.id;
              accepted.add(source);
            }
            return book;
          },
        );
        for (final file in prepared) {
          file.done = accepted.contains(file);
          file.error = !file.done;
        }
        await checkpoint();
        await _releaseCopies(accepted);
        changed();
        notifyListeners();
      }
      if (applyCovers && !stopRequested) {
        stage = ImportStage.covers;
        notifyListeners();
        final ids = books
            .where((f) => f.done)
            .map((f) => f.bookId)
            .whereType<String>()
            .toSet();
        final known = (await repository.getBooks())
            .where((b) => books.isEmpty || ids.contains(b.id))
            .toList();
        final imageGroups = <String, List<ImportSource>>{};
        for (final file in files.where((f) => f.image)) {
          imageGroups.putIfAbsent(coverMatchKey(file.name), () => []).add(file);
        }
        final names = <String, int>{};
        for (final book in known) {
          if (book.matchingFileName != null) {
            names.update(
              coverMatchKey(book.matchingFileName!),
              (n) => n + 1,
              ifAbsent: () => 1,
            );
          }
        }
        final matches = <String, ImportSource>{};
        for (final book in known) {
          final key = book.matchingFileName == null
              ? ''
              : coverMatchKey(book.matchingFileName!);
          final images = imageGroups[key] ?? [];
          if (book.coverPath == null &&
              images.length == 1 &&
              names[key] == 1 &&
              !images.single.done) {
            matches[book.id] = images.single;
          }
        }
        final entries = matches.entries.toList();
        for (
          var offset = 0;
          offset < entries.length && !stopRequested;
          offset += 16
        ) {
          final prepared = <String, BookImportFile>{};
          for (final entry in entries.skip(offset).take(16)) {
            if (stopRequested) break;
            final image = entry.value;
            image.error = false;
            try {
              await prepare(image);
              prepared[entry.key] = BookImportFile(image.name, image.path);
            } catch (_) {
              if (!stopRequested) image.error = true;
            }
          }
          if (stopRequested) {
            await checkpoint();
            break;
          }
          stage = ImportStage.covers;
          notifyListeners();
          final result = await applyCoverMatches(
            repository,
            prepared,
            replaceExisting: false,
            onProgress: (_, __) => notifyListeners(),
          );
          for (final entry in prepared.entries) {
            final image = matches[entry.key]!;
            image.error = result.failures.contains(image.name);
            image.done = !image.error;
          }
          await checkpoint();
          await _releaseCopies(
            prepared.keys.map((id) => matches[id]!).where((file) => file.done),
          );
          changed();
        }
        await checkpoint();
        changed();
      }
      if (group.isNotEmpty && !stopRequested) {
        stage = ImportStage.grouping;
        notifyListeners();
        final all = await groups.load();
        final targetId = group == 'new' ? createdGroupId! : group;
        final existing = all.where((g) => g.id == targetId).firstOrNull;
        final occupied = all.expand((g) => g.bookIds).toSet();
        final available = (await repository.getBooks())
            .map((b) => b.id)
            .toSet();
        final ids = books
            .where(
              (f) =>
                  f.done &&
                  available.contains(f.bookId) &&
                  !occupied.contains(f.bookId),
            )
            .map((f) => f.bookId!)
            .toSet()
            .toList();
        if (existing != null && ids.isNotEmpty) {
          await groups.add(targetId, ids);
        } else if (group == 'new' && existing == null && ids.length >= 2) {
          await groups.create(groupTitle, ids, id: targetId);
        } else if (existing == null && ids.isNotEmpty) {
          message = '책은 등록했습니다. 묶음은 서재에서 확인해 주세요.';
        }
        await checkpoint();
        changed();
      }
    } catch (_) {
      message = '일부 작업을 완료하지 못했습니다. 남은 파일을 다시 시도해 주세요.';
    } finally {
      stage = stopRequested ? ImportStage.review : ImportStage.finished;
      current = '';
      notifyListeners();
    }
  }

  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _releaseCopies(Iterable<ImportSource> sources) async {
    final root = await (await _temporaryDirectory()).resolveSymbolicLinks();
    for (final file in sources) {
      if (file.path == null) continue;
      try {
        final directory = File(file.path!).parent;
        final path = await directory.resolveSymbolicLinks();
        if (path.startsWith('$root/koofy_import/')) {
          await directory.delete(recursive: true);
          file.path = null;
        }
      } catch (_) {
        /* The OS may already have reclaimed this cache file. */
      }
    }
  }

  Future<void> reset() async {
    if (busy) return;
    await storage.remove(importJournalKey);
    await _releaseCopies(files);
    for (final file in files) {
      try {
        await channel.invokeMethod<void>('release', {'source': file.source});
      } catch (_) {}
    }
    files = [];
    stage = ImportStage.idle;
    group = '';
    groupTitle = '';
    createdGroupId = null;
    message = '';
    interrupted = false;
    notifyListeners();
  }
}
