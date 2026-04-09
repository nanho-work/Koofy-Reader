import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/data/reader_settings_repository.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

class ReaderBootstrapData {
  const ReaderBootstrapData({
    required this.content,
    required this.settings,
    required this.bookmarks,
    required this.progress,
    required this.searchHistory,
  });

  final String content;
  final ReaderSettings settings;
  final Set<int> bookmarks;
  final ReadingProgress? progress;
  final List<String> searchHistory;
}

class ReaderPaginationResult {
  const ReaderPaginationResult({
    required this.pages,
    required this.pageIndex,
    required this.restoredProgressConsumed,
  });

  final PaginatedText pages;
  final int pageIndex;
  final bool restoredProgressConsumed;
}

class ReaderSessionController {
  ReaderSessionController({
    required ReaderRepository readerRepository,
    required ReaderSettingsRepository settingsRepository,
    required BookRepository bookRepository,
    required TextPaginationEngine paginationEngine,
  }) : _readerRepository = readerRepository,
       _settingsRepository = settingsRepository,
       _bookRepository = bookRepository,
       _paginationEngine = paginationEngine;

  final ReaderRepository _readerRepository;
  final ReaderSettingsRepository _settingsRepository;
  final BookRepository _bookRepository;
  final TextPaginationEngine _paginationEngine;

  Future<ReaderBootstrapData> bootstrap(Book book) async {
    final results = await Future.wait<dynamic>([
      _bookRepository.readBookContent(book),
      _settingsRepository.load(),
      _readerRepository.loadBookmarks(book.id),
      _readerRepository.loadProgress(book.id),
      _readerRepository.loadSearchHistory(),
    ]);

    final rawContent = results[0] as String;
    final normalized = rawContent
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    return ReaderBootstrapData(
      content: normalized,
      settings: results[1] as ReaderSettings,
      bookmarks: (results[2] as Set<int>).where((page) => page >= 0).toSet(),
      progress: results[3] as ReadingProgress?,
      searchHistory: results[4] as List<String>,
    );
  }

  Future<ReaderPaginationResult> paginate({
    required String bookId,
    required String content,
    required String signature,
    required Size textArea,
    required TextStyle textStyle,
    required int spreadStep,
    required ReadingProgress? restoredProgress,
    required int previousTotalPages,
    required double previousRatio,
  }) async {
    final cachedOffsets = await _readerRepository.loadPaginationOffsets(
      bookId: bookId,
      signature: signature,
      contentLength: content.length,
    );

    PaginatedText paginated;
    if (cachedOffsets != null && cachedOffsets.isNotEmpty) {
      paginated = PaginatedText.fromBreakOffsets(
        source: content,
        offsets: cachedOffsets,
      );
    } else {
      paginated = await _paginationEngine.paginateAsync(
        content: content,
        maxWidth: textArea.width,
        maxHeight: textArea.height,
        style: textStyle,
      );
      await _readerRepository.savePaginationOffsets(
        bookId: bookId,
        signature: signature,
        contentLength: content.length,
        offsets: paginated.toBreakOffsets(),
      );
    }

    final resolved = _resolvePageIndex(
      totalPages: paginated.length,
      spreadStep: spreadStep,
      restoredProgress: restoredProgress,
      previousTotalPages: previousTotalPages,
      previousRatio: previousRatio,
    );

    return ReaderPaginationResult(
      pages: paginated,
      pageIndex: resolved.pageIndex,
      restoredProgressConsumed: resolved.consumedRestoredProgress,
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

  _ResolvedPageIndex _resolvePageIndex({
    required int totalPages,
    required int spreadStep,
    required ReadingProgress? restoredProgress,
    required int previousTotalPages,
    required double previousRatio,
  }) {
    int nextIndex = 0;
    bool consumedRestored = false;

    if (restoredProgress != null) {
      consumedRestored = true;
      if (restoredProgress.totalPages == totalPages &&
          restoredProgress.pageIndex >= 0 &&
          restoredProgress.pageIndex < totalPages) {
        nextIndex = restoredProgress.pageIndex;
      } else {
        nextIndex = (restoredProgress.positionRatio * (totalPages - 1)).round();
      }
    } else if (previousTotalPages > 1) {
      nextIndex = (previousRatio * (totalPages - 1)).round();
    }

    nextIndex = _clampPageIndex(
      nextIndex,
      totalPages: totalPages,
      step: spreadStep,
    );
    return _ResolvedPageIndex(
      pageIndex: nextIndex,
      consumedRestoredProgress: consumedRestored,
    );
  }

  int _clampPageIndex(
    int target, {
    required int totalPages,
    required int step,
  }) {
    if (totalPages <= 1) {
      return 0;
    }
    if (step == 1) {
      return target.clamp(0, totalPages - 1);
    }
    final lastSpreadStart = ((totalPages - 1) ~/ 2) * 2;
    final snapped = (target ~/ 2) * 2;
    return snapped.clamp(0, lastSpreadStart);
  }
}

class _ResolvedPageIndex {
  const _ResolvedPageIndex({
    required this.pageIndex,
    required this.consumedRestoredProgress,
  });

  final int pageIndex;
  final bool consumedRestoredProgress;
}
