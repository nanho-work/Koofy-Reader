import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStorage extends SharedPrefsLocalStorage {
  bool failWrites = false;

  @override
  Future<void> setString(String key, String value) async {
    if (failWrites) throw StateError('storage unavailable');
    await super.setString(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory coversDirectory;
  late File source;
  late SharedPrefsLocalStorage storage;
  late LocalBookRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temporary = await Directory.systemTemp.createTemp('book_covers_test_');
    coversDirectory = Directory('${temporary.path}/covers');
    storage = SharedPrefsLocalStorage();
    repository = LocalBookRepository(
      storage,
      covers: BookCoverStore(storage, directory: () async => coversDirectory),
    );
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 2400, 1200),
      ui.Paint()..color = const ui.Color(0xff365347),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(2400, 1200);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    source = await File(
      '${temporary.path}/source.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });

  tearDown(() async => temporary.delete(recursive: true));

  test(
    'failed preference writes preserve the old cover and remove the new file',
    () async {
      final failing = _FailingStorage();
      final store = BookCoverStore(
        failing,
        directory: () async => coversDirectory,
      );
      final books = await repository.getBooks();
      await store.setImage(books.first.id, source.path);
      final previous = (await store.apply(books)).first.coverPath!;
      failing.failWrites = true;
      await expectLater(
        store.setImage(books.first.id, source.path),
        throwsStateError,
      );
      await expectLater(store.reset(books.first.id), throwsStateError);
      expect((await store.apply(books)).first.coverPath, previous);
      expect(await File(previous).exists(), isTrue);
      expect(await coversDirectory.list().length, 1);
    },
  );

  test(
    'imported book cover survives source deletion and repository restart',
    () async {
      final text = await File(
        '${temporary.path}/my-book.txt',
      ).writeAsString('본문');
      final book = (await repository.importBookFile(text.path))!;
      await repository.setBookCover(book.id, source.path);
      await source.delete();

      final restarted = LocalBookRepository(
        SharedPrefsLocalStorage(),
        covers: BookCoverStore(
          SharedPrefsLocalStorage(),
          directory: () async => coversDirectory,
        ),
      );
      final restored = (await restarted.getBooks()).firstWhere(
        (b) => b.id == book.id,
      );
      expect(restored.localPath, text.path);
      expect(restored.title, book.title);
      expect(restored.coverPath, startsWith(coversDirectory.path));
      final codec = await ui.instantiateImageCodec(
        await File(restored.coverPath!).readAsBytes(),
      );
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 1200);
      expect(image.height, 600);
      image.dispose();
      codec.dispose();

      // The persisted filename remains valid if an iOS application container moves.
      final moved = await coversDirectory.rename('${temporary.path}/moved');
      coversDirectory = moved;
      final relocated = (await restarted.getBooks()).firstWhere(
        (b) => b.id == book.id,
      );
      expect(await File(relocated.coverPath!).exists(), isTrue);
    },
  );

  test('replacement and reset clean up only managed cover files', () async {
    await repository.setBookCover('sample_1', source.path);
    final first = (await repository.getBooks()).first;
    await repository.setBookCover('sample_1', source.path);
    final second = (await repository.getBooks()).first;
    expect(second.coverPath, isNot(first.coverPath));
    expect(await File(first.coverPath!).exists(), isFalse);
    expect(await source.exists(), isTrue);
    await repository.resetBookCover('sample_1');
    expect((await repository.getBooks()).first.coverPath, isNull);
    expect(await File(second.coverPath!).exists(), isFalse);
    expect(await source.exists(), isTrue);
  });

  test('invalid and oversized images leave current cover intact', () async {
    await repository.setBookCover('sample_1', source.path);
    final before = (await repository.getBooks()).first.coverPath;
    final invalid = await File(
      '${temporary.path}/invalid.jpg',
    ).writeAsString('not an image');
    await expectLater(
      repository.setBookCover('sample_1', invalid.path),
      throwsA(anything),
    );
    final large = await File(
      '${temporary.path}/large.png',
    ).open(mode: FileMode.write);
    await large.truncate(BookCoverStore.maxBytes + 1);
    await large.close();
    await expectLater(
      repository.setBookCover('sample_1', '${temporary.path}/large.png'),
      throwsFormatException,
    );
    expect((await repository.getBooks()).first.coverPath, before);
    expect(await File(before!).exists(), isTrue);
    expect(await coversDirectory.list().length, 1);
  });

  test(
    'download updates preserve personal cover and deletion retains originals',
    () async {
      final epub = await File(
        '${temporary.path}/original.epub',
      ).writeAsString('epub');
      final downloaded = Book.localFile(
        id: 'downloaded',
        title: '책',
        author: '작가',
        description: '',
        localPath: epub.path,
        coverPath: source.path,
      );
      await repository.saveDownloadedBook(downloaded);
      await repository.setBookCover(downloaded.id, source.path);
      final personal = (await repository.getBooks()).first.coverPath!;
      await repository.saveDownloadedBook(downloaded);
      expect((await repository.getBooks()).first.coverPath, personal);
      await repository.resetBookCover(downloaded.id);
      expect((await repository.getBooks()).first.coverPath, isNull);
      expect(await source.exists(), isTrue);
      await repository.setBookCover(downloaded.id, source.path);
      final lastCover = (await repository.getBooks()).first.coverPath!;
      await repository.removeBookFromLibrary(downloaded.id);
      expect(await File(lastCover).exists(), isFalse);
      expect(await source.exists(), isTrue);
      expect(await epub.exists(), isTrue);
      expect(
        (await repository.getBooks()).any((b) => b.id == downloaded.id),
        isFalse,
      );
    },
  );
}
