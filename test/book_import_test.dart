import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/application/book_import.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingBookRepository extends LocalBookRepository {
  FailingBookRepository(super.storage);
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
  test(
    'batch keeps all ten books, skips duplicates and continues after failures',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('koofy-batch-');
      addTearDown(() => directory.delete(recursive: true));
      final repository = FailingBookRepository(SharedPrefsLocalStorage());
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
      expect(result.existing, 1);
      expect(result.failedNames, ['broken.txt', 'cloud.txt']);
      expect(progress, List.generate(13, (i) => i + 1));
      expect(
        (await repository.getBooks()).where((b) => b.isLocalFile),
        hasLength(10),
      );
      final retry = await importBooks(repository, [files.first]);
      expect(retry.added, 0);
      expect(retry.existing, 1);
    },
  );
}
