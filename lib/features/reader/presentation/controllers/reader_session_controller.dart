import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/data/reader_settings_repository.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/engine/reader_engine.dart';

class ReaderBootstrapData {
  const ReaderBootstrapData({
    required this.content,
    required this.settings,
    required this.bookmarks,
    required this.progress,
    required this.searchHistory,
    required this.structureIndex,
  });

  final String content;
  final ReaderSettings settings;
  final Set<int> bookmarks;
  final ReadingProgress? progress;
  final List<String> searchHistory;
  final ReaderStructureIndex? structureIndex;
}

class ReaderSessionController {
  ReaderSessionController({
    required ReaderRepository readerRepository,
    required ReaderSettingsRepository settingsRepository,
    required BookRepository bookRepository,
    required ReaderEngine engine,
  }) : _readerRepository = readerRepository,
       _settingsRepository = settingsRepository,
       _bookRepository = bookRepository,
       _engine = engine;

  final ReaderRepository _readerRepository;
  final ReaderSettingsRepository _settingsRepository;
  final BookRepository _bookRepository;
  final ReaderEngine _engine;

  Future<ReaderBootstrapData> bootstrap(Book book) async {
    final results = await Future.wait<dynamic>([
      _bookRepository.readBookContent(book),
      _settingsRepository.load(),
      _readerRepository.loadBookmarks(book.id),
      _readerRepository.loadProgress(book.id),
      _readerRepository.loadSearchHistory(),
    ]);

    final rawContent = results[0] as String;
    final normalized = _engine.normalizeContent(rawContent);
    final contentHash = _engine.stableHash(normalized);
    var structureIndex = await _readerRepository.loadStructureIndex(
      bookId: book.id,
      contentLength: normalized.length,
      contentHash: contentHash,
    );
    if (structureIndex == null) {
      structureIndex = _engine.buildStructureIndex(
        content: normalized,
        contentHash: contentHash,
      );
      await _readerRepository.saveStructureIndex(
        bookId: book.id,
        index: structureIndex,
      );
    }

    return ReaderBootstrapData(
      content: normalized,
      settings: results[1] as ReaderSettings,
      bookmarks: (results[2] as Set<int>).where((page) => page >= 0).toSet(),
      progress: results[3] as ReadingProgress?,
      searchHistory: results[4] as List<String>,
      structureIndex: structureIndex,
    );
  }

  Future<void> saveProgress(ReadingProgress progress) {
    return _readerRepository.saveProgress(progress);
  }

  Future<void> saveBookmarks(String bookId, Set<int> bookmarks) {
    return _readerRepository.saveBookmarks(bookId, bookmarks);
  }

  Future<void> saveSearchHistory(List<String> history) {
    return _readerRepository.saveSearchHistory(history);
  }

  Future<void> saveSettings(ReaderSettings settings) {
    return _settingsRepository.save(settings);
  }
}
