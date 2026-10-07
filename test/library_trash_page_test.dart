import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_trash_service.dart';
import 'package:koofy_reader/features/library/data/library_trash_store.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/library_trash_page.dart';
import 'reader_catalog_test.dart' show MemoryStorage;

class UiTrashService extends LibraryTrashService {
  UiTrashService(super.storage, super.support, this.file)
    : super(deleteReadingRecords: (_) async {});
  final File file;
  final removed = <String>{};
  @override
  Future<int> bytes(Set<String> keys) async =>
      file.existsSync() ? file.lengthSync() : 0;
  @override
  Future<void> empty(Set<String> keys) async {
    removed.addAll(keys);
    file.deleteSync();
    for (final id in keys) {
      await trash.forget(id);
    }
  }
}

void main() {
  testWidgets(
    'trash offers restore, permanent delete and confirmed emptying at large text',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('trash_ui_');
      addTearDown(() => root.deleteSync(recursive: true));
      final storage = MemoryStorage();
      final store = LibraryTrashStore(storage);
      final books = LocalBookRepository(storage);
      final source = File('${root.path}/library_sources/a.txt');
      source.parent.createSync(recursive: true);
      source.writeAsStringSync('body');
      final book = Book.localFile(
        id: 'a',
        title: '휴지통 테스트 도서',
        author: '작가',
        description: '',
        localPath: source.path,
      );
      await tester.runAsync(() => books.saveDownloadedBook(book));
      await store.moveBook(book);
      final service = UiTrashService(storage, root, source);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localStorageProvider.overrideWithValue(storage),
            libraryTrashServiceProvider.overrideWith((ref) async => service),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const LibraryTrashPage(),
          ),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('복원'), findsOneWidget);
      expect(find.text('영구 삭제'), findsOneWidget);
      expect(find.text('휴지통 비우기'), findsOneWidget);
      await tester.ensureVisible(find.text('영구 삭제'));
      await tester.tap(find.text('영구 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(source.existsSync(), true);
      expect(service.removed, isEmpty);
      expect((await store.load()).length, 1);
      await tester.tap(find.text('휴지통 비우기'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '영구 삭제'));
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
      expect(source.existsSync(), false);
      expect(service.removed, {'a'});
      expect(await store.load(), isEmpty);
      expect(find.text('휴지통이 비어 있습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
