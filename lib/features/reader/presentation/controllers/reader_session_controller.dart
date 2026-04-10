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
  static final Map<String, List<int>> _runtimePaginationOffsets = {};

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
    int previewPageCount = 30,
    ValueChanged<PaginatedText>? onPreviewReady,
  }) async {
    final runtimeCacheKey = '$bookId|$signature|${content.length}';
    final runtimeOffsets = _runtimePaginationOffsets[runtimeCacheKey];
    final cachedOffsets =
        runtimeOffsets ??
        await _readerRepository.loadPaginationOffsets(
          bookId: bookId,
          signature: signature,
          contentLength: content.length,
        );

    PaginatedText paginated;
    if (cachedOffsets != null && cachedOffsets.isNotEmpty) {
      _runtimePaginationOffsets[runtimeCacheKey] = cachedOffsets;
      paginated = PaginatedText.fromBreakOffsets(
        source: content,
        offsets: cachedOffsets,
      );
    } else {
      final canUsePreview = onPreviewReady != null && previewPageCount > 0;

      PaginatedText? preview;
      if (canUsePreview) {
        preview = await _paginationEngine.paginateAsync(
          content: content,
          maxWidth: textArea.width,
          maxHeight: textArea.height,
          style: textStyle,
          yieldEvery: 1,
          maxPages: previewPageCount,
        );
        if (preview.length > 0) {
          onPreviewReady(preview);
        }
      }

      final previewCoveredAll =
          preview != null &&
          preview.ranges.isNotEmpty &&
          preview.ranges.last.end >= content.length;

      paginated = previewCoveredAll
          ? preview
          : await _paginationEngine.paginateAsync(
              content: content,
              maxWidth: textArea.width,
              maxHeight: textArea.height,
              style: textStyle,
              yieldEvery: 1,
            );

      final offsets = paginated.toBreakOffsets();
      _runtimePaginationOffsets[runtimeCacheKey] = offsets;
      await _readerRepository.savePaginationOffsets(
        bookId: bookId,
        signature: signature,
        contentLength: content.length,
        offsets: offsets,
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

  Future<void> precomputePaginationCache({
    required String bookId,
    required String content,
    required String signature,
    required Size textArea,
    required TextStyle textStyle,
  }) async {
    final runtimeCacheKey = '$bookId|$signature|${content.length}';
    if (_runtimePaginationOffsets.containsKey(runtimeCacheKey)) {
      return;
    }

    final cachedOffsets = await _readerRepository.loadPaginationOffsets(
      bookId: bookId,
      signature: signature,
      contentLength: content.length,
    );
    if (cachedOffsets != null && cachedOffsets.isNotEmpty) {
      _runtimePaginationOffsets[runtimeCacheKey] = cachedOffsets;
      return;
    }

    final pages = await _paginationEngine.paginateAsync(
      content: content,
      maxWidth: textArea.width,
      maxHeight: textArea.height,
      style: textStyle,
      yieldEvery: 1,
    );
    final offsets = pages.toBreakOffsets();
    if (offsets.isEmpty) {
      return;
    }
    _runtimePaginationOffsets[runtimeCacheKey] = offsets;
    await _readerRepository.savePaginationOffsets(
      bookId: bookId,
      signature: signature,
      contentLength: content.length,
      offsets: offsets,
    );
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
