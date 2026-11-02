import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/features/library/application/book_import_controller.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';

class MemoryStorage implements LocalStorage {
  final values = <String, String>{};
  final writes = <String, int>{};
  @override
  Future<String?> getString(String key) async => values[key];
  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
    writes.update(key, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix) async =>
      Map.fromEntries(values.entries.where((e) => e.key.startsWith(prefix)));
  @override
  Future<int?> getInt(String key) async => int.tryParse(values[key] ?? '');
  @override
  Future<void> setInt(String key, int value) async {
    values[key] = '$value';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('koofy_reader/book_import');
  late Directory root;
  late MemoryStorage storage;
  late LocalBookRepository repository;
  late BookGroupRepository groups;
  late BookImportController job;
  late List<int> png;
  var timeout = const Duration(seconds: 90);
  var copyCalls = 0;
  var count = 0;
  var images = false;
  String? broken;
  bool nativeBusy = false;
  Completer<void>? hold;
  Completer<void>? started;
  Future<dynamic> native(MethodCall call) async {
    if (call.method == 'pick') {
      return [
        for (var i = 1; i <= count; i++)
          for (final ext in ['txt', if (images) 'png'])
            {
              'name': '${i.toString().padLeft(3, '0')}_title.$ext',
              'source': 'content://test/$i.$ext',
            },
      ];
    }
    if (call.method == 'cancel') {
      hold?.complete();
      hold = null;
      return null;
    }
    if (call.method != 'copy') return null;
    copyCalls++;
    if (nativeBusy) throw PlatformException(code: 'busy');
    final args = Map<String, dynamic>.from(call.arguments as Map);
    final name = args['name'] as String;
    if (name.startsWith('017_') && hold != null) {
      started!.complete();
      await hold!.future;
      throw PlatformException(code: 'cancelled');
    }
    if (name == broken) throw PlatformException(code: 'unavailable');
    final file = File(
      '${root.path}/cache/koofy_import/${args['source'].hashCode}/$name',
    );
    await file.parent.create(recursive: true);
    if (name.endsWith('.png')) {
      await file.writeAsBytes(png);
    } else {
      await file.writeAsString('제목 $name\n\n각각의 원고 내용 ${args['source']}');
    }
    return file.path;
  }

  BookImportController create() => BookImportController(
    storage,
    repository,
    groups,
    changed: () {},
    copyTimeout: timeout,
    temporaryDirectory: () async => Directory('${root.path}/cache'),
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 2, 2),
      ui.Paint()..color = const ui.Color(0xff91af9d),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
    root = await Directory.systemTemp.createTemp('koofy-import-job-');
    storage = MemoryStorage();
    copyCalls = 0;
    timeout = const Duration(seconds: 90);
    count = 0;
    images = false;
    broken = null;
    nativeBusy = false;
    hold = null;
    started = null;
    repository = LocalBookRepository(
      storage,
      sourceDirectory: () async => Directory('${root.path}/library'),
      covers: BookCoverStore(
        storage,
        directory: () async => Directory('${root.path}/covers'),
      ),
    );
    groups = BookGroupRepository(storage);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native);
    job = create();
    await job.ready;
  });
  tearDown(() async {
    job.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });
  test(
    '250 manuscripts and matching images commit in batches and retry without duplicates',
    () async {
      count = 250;
      images = true;
      await job.pick();
      expect(copyCalls, 0);
      expect(job.files.length, 500);
      job.group = 'new';
      job.groupTitle = '250화 묶음';
      await job.run();
      expect(job.completed, 250);
      expect(job.failures, 0);
      expect(job.message, isEmpty);
      expect(copyCalls, 500);
      final books = (await repository.getBooks())
          .where((b) => b.isLocalFile)
          .toList();
      expect(books.length, 250);
      expect(
        books.every(
          (b) => b.coverPath != null && File(b.coverPath!).existsSync(),
        ),
        isTrue,
      );
      expect((await groups.load()).single.bookIds.length, 250);
      expect(storage.writes[AppConstants.localBooksKey], lessThanOrEqualTo(16));
      expect(
        await Directory(
          '${root.path}/cache/koofy_import',
        ).list(recursive: true).where((entry) => entry is File).isEmpty,
        isTrue,
      );
      await job.run();
      expect(copyCalls, 500);
      expect((await groups.load()).length, 1);
      expect(
        (await repository.getBooks()).where((b) => b.isLocalFile).length,
        250,
      );
      await job.reset();
      expect(storage.values.containsKey(importJournalKey), isFalse);
      expect(
        (await repository.getBooks()).where((b) => b.isLocalFile).length,
        250,
      );
      expect(books.every((b) => File(b.localPath!).existsSync()), isTrue);
    },
  );
  test(
    'stop checkpoints committed chunk and restart resumes the remainder and group once',
    () async {
      count = 32;
      await job.pick();
      job.group = 'new';
      job.groupTitle = '계속 읽기';
      hold = Completer<void>();
      started = Completer<void>();
      final running = job.run();
      await started!.future;
      expect(job.completed, 16);
      await job.stop();
      await running;
      expect(job.stage, ImportStage.review);
      final stableGroupId = job.createdGroupId;
      job.dispose();
      job = create();
      await job.ready;
      expect(job.completed, 16);
      expect(job.createdGroupId, stableGroupId);
      await job.run();
      expect(job.completed, 32);
      expect(
        (await repository.getBooks()).where((b) => b.isLocalFile).length,
        32,
      );
      expect((await groups.load()).single.id, stableGroupId);
    },
  );
  test(
    'one provider failure does not discard other files and retry fetches only the failed file',
    () async {
      count = 19;
      broken = '004_title.txt';
      await job.pick();
      await job.run();
      expect(job.completed, 18);
      expect(job.failures, 1);
      broken = null;
      nativeBusy = false;
      await job.run();
      expect(job.completed, 19);
      expect(job.failures, 0);
      expect(copyCalls, 20);
      expect(
        (await repository.getBooks()).where((b) => b.isLocalFile).length,
        19,
      );
    },
  );
  test(
    'unresponsive provider pauses instead of marking all remaining files as failed',
    () async {
      job.dispose();
      timeout = const Duration(milliseconds: 100);
      job = create();
      await job.ready;
      count = 32;
      await job.pick();
      hold = Completer<void>();
      started = Completer<void>();
      await job.run();
      expect(job.completed, 16);
      expect(copyCalls, 17);
      expect(job.stage, ImportStage.review);
      expect(job.message, isNotEmpty);
      await job.run();
      expect(job.completed, 32);
      expect(
        (await repository.getBooks()).where((b) => b.isLocalFile).length,
        32,
      );
    },
  );
  test(
    'a native request still stopping pauses retries without failing the whole queue',
    () async {
      count = 20;
      await job.pick();
      nativeBusy = true;
      await job.run();
      expect(copyCalls, 1);
      expect(job.completed, 0);
      expect(job.failures, 0);
      expect(job.stage, ImportStage.review);
      nativeBusy = false;
      await job.run();
      expect(job.completed, 20);
    },
  );
}
