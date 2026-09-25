import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/application/book_import.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';

class FailingBookRepository extends LocalBookRepository {
  FailingBookRepository(super.storage, {super.sourceDirectory});
  @override
  Future<Book?> importBookFile(String path) {
    if (path.endsWith('broken.txt')) {
      throw const FileSystemException('unreadable');
    }
    return super.importBookFile(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unsafe and oversized EPUBs cannot enter the library', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'koofy-import-validation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = LocalBookRepository(
      SharedPrefsLocalStorage(),
      sourceDirectory: () async => Directory('${directory.path}/owned'),
    );
    final unsafe = await File(
      'docs/audits/2026-09-25/remote-resource-fixture.epub',
    ).copy('${directory.path}/unsafe.epub');
    await expectLater(
      repository.importBookFile(unsafe.path),
      throwsA(
        isA<ReadingPublicationPreparationException>().having(
          (e) => e.code,
          'code',
          'active_content',
        ),
      ),
    );
    final huge = File('${directory.path}/huge.epub');
    final handle = await huge.open(mode: FileMode.write);
    await handle.truncate(40 * 1024 * 1024 + 1);
    await handle.close();
    await expectLater(
      repository.importBookFile(huge.path),
      throwsFormatException,
    );
    expect((await repository.getBooks()).where((b) => b.isLocalFile), isEmpty);
    expect(await Directory('${directory.path}/owned').exists(), false);
  });

  test(
    'batch keeps all ten books, skips duplicates and continues after failures',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('koofy-batch-');
      addTearDown(() => directory.delete(recursive: true));
      final repository = FailingBookRepository(
        SharedPrefsLocalStorage(),
        sourceDirectory: () async => Directory('${directory.path}/owned'),
      );
      final files = <BookImportFile>[];
      for (var i = 1; i <= 10; i++) {
        final name = '$i화.txt';
        final file = await File(
          '${directory.path}/$name',
        ).writeAsString('제$i화 본문');
        files.add(BookImportFile(name, file.path));
      }
      files.insert(3, const BookImportFile('broken.txt', '/broken.txt'));
      files.insert(4, const BookImportFile('cloud.txt', null));
      files.add(files.first);
      final progress = <int>[];
      final result = await importBooks(
        repository,
        files,
        onProgress: (done, total) {
          expect(total, 13);
          progress.add(done);
        },
      );
      expect(result.added, 10);
      expect(result.addedIds, hasLength(10));
      expect(
        result.addedIds.toSet(),
        (await repository.getBooks())
            .where((b) => b.isLocalFile)
            .map((b) => b.id)
            .toSet(),
      );
      expect(result.existing, 1);
      expect(result.failedNames, ['broken.txt', 'cloud.txt']);
      expect(progress, List.generate(13, (i) => i + 1));
      expect(
        (await repository.getBooks()).where((b) => b.isLocalFile),
        hasLength(10),
      );
      final retry = await importBooks(repository, [files.first]);
      expect(retry.added, 0);
      expect(retry.addedIds, isEmpty);
      expect(retry.existing, 1);
    },
  );
}
