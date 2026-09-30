import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/application/legacy_text_import.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/library_trash_store.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/presentation/widgets/book_tile.dart';
import 'package:koofy_reader/features/library/presentation/text_import_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LocalBookRepository repo;
  late File legacyFile;
  late SharedPrefsLocalStorage storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = SharedPrefsLocalStorage();
    dir = await Directory.systemTemp.createTemp('koofy-enhance-');
    legacyFile = await File(
      '${dir.path}/old.txt',
    ).writeAsBytes([0xb0, 0xa1, 0xb3, 0xaa]);
    repo = LocalBookRepository(
      storage,
      sourceDirectory: () async => Directory('${dir.path}/owned'),
    );
  });
  tearDown(() => dir.delete(recursive: true));
  test(
    'CP949 and EUC-KR strict decoding rejects truncation and binary',
    () async {
      final map = await File('assets/encoding/cp949.bin').readAsBytes();
      expect(
        LegacyTextImport.decode(
          Uint8List.fromList([0xb0, 0xa1, 0xb3, 0xaa, 10, 0x81, 0x41]),
          map,
        ),
        '가나\n갂',
      );
      expect(
        () => LegacyTextImport.decode(Uint8List.fromList([0x81]), map),
        throwsFormatException,
      );
      expect(
        () => LegacyTextImport.decode(Uint8List.fromList([0x81, 0x30]), map),
        throwsFormatException,
      );
      expect(
        () => LegacyTextImport.decode(Uint8List.fromList([0]), map),
        throwsFormatException,
      );
    },
  );
  test(
    'renamed copies deduplicate but changed content at the same picker path imports',
    () async {
      final input = await File('${dir.path}/a.txt').writeAsString('첫 내용');
      final a = (await repo.importBookFile(input.path))!;
      final copied = await input.copy('${dir.path}/different.txt');
      expect((await repo.importBookFile(copied.path))!.id, a.id);
      await input.writeAsString('변경된 내용');
      expect((await repo.importBookFile(input.path))!.id, isNot(a.id));
      expect(await File(a.localPath!).readAsString(), '첫 내용');
    },
  );
  test(
    'trash survives restart, leaves source and group membership intact, and restores',
    () async {
      final input = await File('${dir.path}/a.txt').writeAsString('읽던 본문');
      final a = (await repo.importBookFile(input.path))!;
      final groups = BookGroupRepository(storage);
      await groups.create('묶음', [a.id, 'sample_1']);
      final original = (await groups.load()).single;
      await storage.setString('reader-test-position-${a.id}', 'saved position');
      await LibraryTrashStore(storage).moveBook(a);
      expect((await repo.getBooks()).any((b) => b.id == a.id), false);
      expect(await File(a.localPath!).readAsString(), '읽던 본문');
      expect((await groups.load()).single.bookIds, original.bookIds);
      final restarted = LibraryTrashStore(SharedPrefsLocalStorage());
      expect(await restarted.hiddenBookIds(), contains(a.id));
      await restarted.restoreBook(a.id);
      expect((await repo.getBooks()).any((b) => b.id == a.id), true);
      expect(
        await storage.getString('reader-test-position-${a.id}'),
        'saved position',
      );
      await groups.dissolve(original.id);
      final snapshot = (await restarted.load())[original.id]!;
      await groups.create('새 묶음', [a.id, 'sample_2']);
      await groups.restoreGroup(
        BookGroup.fromJson(Map<String, dynamic>.from(snapshot['group'] as Map)),
        {a.id, 'sample_1', 'sample_2'},
      );
      expect(
        (await groups.load()).firstWhere((g) => g.id == original.id).bookIds,
        ['sample_1'],
      );
      expect((await restarted.load()).containsKey(original.id), false);
    },
  );
  test('downloading a trashed catalog book makes it visible again', () async {
    final source = await File('${dir.path}/catalog.txt').writeAsString('본문');
    final book = Book.localFile(
      id: 'catalog_test',
      title: '제공 도서',
      author: '',
      description: '',
      localPath: source.path,
    );
    await repo.saveDownloadedBook(book);
    await LibraryTrashStore(storage).moveBook(book);
    expect((await repo.getBooks()).any((b) => b.id == book.id), false);
    await repo.saveDownloadedBook(book);
    expect((await repo.getBooks()).where((b) => b.id == book.id), hasLength(1));
    expect(
      await LibraryTrashStore(storage).hiddenBookIds(),
      isNot(contains(book.id)),
    );
  });
  testWidgets(
    'legacy import asks for preview and never changes original bytes',
    (tester) async {
      final source = legacyFile;
      Book? imported;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                imported = await importWithTextPreview(
                  context,
                  repo,
                  source.path,
                );
              },
              child: const Text('가져오기'),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('가져오기'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pumpAndSettle();
      expect(find.text('한글 텍스트 확인'), findsOneWidget);
      expect(imported, isNull);
      await tester.runAsync(() async {
        await tester.tap(find.text('확인 후 가져오기'));
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pumpAndSettle();
      expect(imported, isNotNull);
      await tester.runAsync(() async {
        expect(await source.readAsBytes(), [0xb0, 0xa1, 0xb3, 0xaa]);
        expect(
          utf8.decode(await File(imported!.localPath!).readAsBytes()),
          '가나',
        );
      });
    },
  );
  testWidgets(
    'group menu is at cover top and cannot open the group accidentally',
    (tester) async {
      final book = Book.asset(
        id: 'g',
        title: '묶음',
        author: '책 묶음',
        description: '',
        assetPath: 'unused',
      );
      for (final width in [96.0, 220.0]) {
        var open = 0, more = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: 350,
                  child: BookTile(
                    book: book,
                    onTap: () => open++,
                    onMore: () => more++,
                    statusLabel: '미독',
                    badge: '12권 묶음',
                  ),
                ),
              ),
            ),
          ),
        );
        final menu = find.byTooltip('묶음 더보기');
        final badge = find.text('12권 묶음');
        expect(
          tester.getCenter(menu).dy,
          closeTo(tester.getCenter(badge).dy, 1),
        );
        expect(tester.getTopLeft(menu).dy, lessThan(30));
        await tester.tap(menu);
        expect(more, 1);
        expect(open, 0);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
