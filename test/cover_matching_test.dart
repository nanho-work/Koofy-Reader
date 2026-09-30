import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/application/book_import.dart';
import 'package:koofy_reader/features/library/application/cover_matching.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/batch_cover_page.dart';

Book book(String id, String? name, {String? cover}) => Book.localFile(
  id: id,
  title: '바뀐 제목 $id',
  author: '저자',
  description: '',
  localPath: '/owned/$id/source.txt',
  originalFileName: name,
  coverPath: cover,
);

class CoverRepository extends LocalBookRepository {
  CoverRepository(this.books) : super(SharedPrefsLocalStorage());
  final List<Book> books;
  final saved = <String>[];
  @override
  Future<List<Book>> getBooks() async => books;
  @override
  Future<void> setBookCover(String id, String path) async {
    if (path == '/broken') throw const FormatException('broken');
    saved.add(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('matches original names, final extension, case and selected scope', () {
    final first = book('1', '소설.001.TXT');
    final plan = CoverMatchPlan(
      [first, book('2', null)],
      const [
        BookImportFile('소설.001.PNG', '/1'),
        BookImportFile('다른.jpg', '/2'),
      ],
    );
    expect(plan.matches.single.book.id, '1');
    expect(plan.unmatchedImages.single.name, '다른.jpg');
    expect(plan.needsChoice(plan.matches.single), false);
    expect(coverMatchKey(r'C:\folder\EP.01.txt'), 'ep.01');
  });
  test(
    'duplicates require explicit choice; unknown original never uses title',
    () {
      final plan = CoverMatchPlan(
        [book('1', 'a.txt'), book('2', 'a.epub'), book('3', null)],
        const [
          BookImportFile('a.jpg', '/1'),
          BookImportFile('a.png', '/2'),
          BookImportFile('바뀐 제목 3.jpg', '/3'),
        ],
      );
      expect(plan.matches, hasLength(2));
      expect(plan.matches.every(plan.needsChoice), true);
      expect(plan.unmatchedImages, hasLength(1));
    },
  );
  test('legacy original filename survives cover change and portable JSON', () {
    final legacy = Book.localFile(
      id: 'legacy',
      title: '수정 제목',
      author: '',
      description: '',
      localPath: '/owned/source.txt',
      importSourcePath: '/cache/소설_01.txt',
    );
    final json = legacy.withCoverPath('/cover.png').toJson()
      ..remove('importSourcePath');
    expect(Book.fromJson(json)!.matchingFileName, '소설_01.txt');
    expect(book('1', null).matchingFileName, isNull);
  });
  test(
    'fresh covers and removed books are protected, failure does not abort',
    () async {
      final repo = CoverRepository([
        book('1', 'a.txt', cover: '/new'),
        book('2', 'b.txt'),
        book('3', 'c.txt'),
      ]);
      final result = await applyCoverMatches(repo, const {
        '1': BookImportFile('a.png', '/1'),
        '2': BookImportFile('b.png', '/broken'),
        '3': BookImportFile('c.png', '/3'),
        'gone': BookImportFile('d.png', '/4'),
      }, replaceExisting: false);
      expect(result.applied, 1);
      expect(result.skipped, 2);
      expect(result.failures, ['b.png']);
      expect(repo.saved, ['3']);
      final replaced = await applyCoverMatches(repo, const {
        '1': BookImportFile('a.png', '/1'),
      }, replaceExisting: true);
      expect(replaced.applied, 1);
    },
  );
  testWidgets(
    'preview preserves existing covers until replacement is enabled',
    (tester) async {
      final b = book('1', 'a.txt', cover: '/cover');
      final repo = CoverRepository([b]);
      await tester.pumpWidget(
        MaterialApp(
          home: BatchCoverPage(
            plan: CoverMatchPlan([b], const [BookImportFile('a.png', '/a')]),
            repository: repo,
            onChanged: () {},
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(find.text('1권에 표지 적용'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
