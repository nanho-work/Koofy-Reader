import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/data/reader_settings_repository.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_session_controller.dart';

void main() {
  group('ReaderSessionController', () {
    test('bootstrap uses prepared content with structure index', () async {
      final book = Book.asset(
        id: 'book-1',
        title: 'sample',
        author: 'tester',
        description: 'desc',
        assetPath: 'assets/books/sample_1.txt',
      );
      final structureIndex = ReaderStructureIndex(
        schemaVersion: ReaderStructureIndex.currentSchemaVersion,
        contentLength: 5,
        contentHash: 'prepared-hash',
        paragraphs: const <ReaderParagraphRangeData>[
          ReaderParagraphRangeData(start: 0, end: 5),
        ],
        chapters: const <ReaderChapterRangeData>[
          ReaderChapterRangeData(
            id: 'root',
            paragraphStartIndex: 0,
            paragraphEndIndex: 1,
          ),
        ],
      );
      final readerRepository = _FakeReaderRepository();
      final controller = ReaderSessionController(
        readerRepository: readerRepository,
        settingsRepository: _FakeReaderSettingsRepository(),
        bookRepository: _FakeBookRepository(
          prepared: PreparedBookContent(
            content: 'a\nb\nc',
            contentHash: 'prepared-hash',
            structureIndex: structureIndex,
          ),
        ),
      );

      final data = await controller.bootstrap(book);

      expect(data.content, 'a\nb\nc');
      expect(data.structureIndex, same(structureIndex));
    });
  });
}

class _FakeBookRepository implements BookRepository {
  _FakeBookRepository({required this.prepared});

  final PreparedBookContent prepared;

  @override
  Future<List<Book>> getBooks() async => const <Book>[];

  @override
  Future<Book?> importBookFile(String path) async => null;

  @override
  Future<bool> removeBookFromLibrary(String bookId) async => false;

  @override
  Future<bool> deleteLocalBook(String bookId) async => false;

  @override
  Future<String> readBookContent(Book book) async => prepared.content;

  @override
  Future<PreparedBookContent> readPreparedBookContent(Book book) async {
    return prepared;
  }
}

class _FakeReaderSettingsRepository implements ReaderSettingsRepository {
  @override
  Future<ReaderSettings> load() async => ReaderSettings.defaults();

  @override
  Future<void> save(ReaderSettings settings) async {}
}

class _FakeReaderRepository implements ReaderRepository {
  @override
  Future<Set<int>> loadBookmarks(String bookId) async => <int>{};

  @override
  Future<Map<String, ReadingProgress>> loadAllProgress() async =>
      <String, ReadingProgress>{};

  @override
  Future<ReadingProgress?> loadProgress(String bookId) async => null;

  @override
  Future<List<String>> loadRecentBookIds() async => const <String>[];

  @override
  Future<List<String>> loadSearchHistory() async => const <String>[];

  @override
  Future<void> saveBookmarks(String bookId, Set<int> pages) async {}

  @override
  Future<void> saveProgress(ReadingProgress progress) async {}

  @override
  Future<void> saveSearchHistory(List<String> history) async {}
}
