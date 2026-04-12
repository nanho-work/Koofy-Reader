import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/data/reader_settings_repository.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

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

class ReaderPaginationResult {
  const ReaderPaginationResult({required this.pages});

  final PaginatedText pages;
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
  static final RegExp _chapterHeadingPattern = RegExp(
    r'^\s*(?:chapter\s+\d+|ch\.?\s*\d+|제\s*\d+\s*장|챕터\s*\d+|#\s+\S+)',
    caseSensitive: false,
  );

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
    final contentHash = _stableHash(normalized);
    var structureIndex = await _readerRepository.loadStructureIndex(
      bookId: book.id,
      contentLength: normalized.length,
      contentHash: contentHash,
    );
    if (structureIndex == null) {
      structureIndex = _buildStructureIndex(
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

  Future<ReaderPaginationResult> paginate({
    required String content,
    required Size textArea,
    required TextStyle textStyle,
    int previewPageCount = 30,
    ValueChanged<PaginatedText>? onPreviewReady,
    bool previewOnly = false,
  }) async {
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

    final PaginatedText paginated;
    if (previewOnly && preview != null && preview.length > 0) {
      paginated = preview;
    } else {
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
    }

    return ReaderPaginationResult(pages: paginated);
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

  ReaderStructureIndex _buildStructureIndex({
    required String content,
    required String contentHash,
  }) {
    final paragraphs = <ReaderParagraphRangeData>[];
    int start = 0;
    while (start < content.length) {
      while (start < content.length && content.codeUnitAt(start) == 0x0A) {
        start++;
      }
      if (start >= content.length) {
        break;
      }
      int end = start;
      while (end < content.length && content.codeUnitAt(end) != 0x0A) {
        end++;
      }
      paragraphs.add(ReaderParagraphRangeData(start: start, end: end));
      start = end;
    }
    if (paragraphs.isEmpty) {
      paragraphs.add(
        ReaderParagraphRangeData(
          start: 0,
          end: content.length.clamp(0, 1 << 30),
        ),
      );
    }

    final chapters = _buildChapterRanges(
      content: content,
      paragraphs: paragraphs,
    );

    return ReaderStructureIndex(
      schemaVersion: ReaderStructureIndex.currentSchemaVersion,
      contentLength: content.length,
      contentHash: contentHash,
      paragraphs: paragraphs,
      chapters: chapters,
    );
  }

  List<ReaderChapterRangeData> _buildChapterRanges({
    required String content,
    required List<ReaderParagraphRangeData> paragraphs,
  }) {
    if (paragraphs.isEmpty) {
      return const <ReaderChapterRangeData>[];
    }

    final markers = _collectChapterMarkers(content);
    if (markers.isEmpty) {
      return [
        ReaderChapterRangeData(
          id: 'root',
          paragraphStartIndex: 0,
          paragraphEndIndex: paragraphs.length,
        ),
      ];
    }

    final seeds = <_ChapterMarkerSeed>[];
    if (markers.first.startOffset > 0) {
      seeds.add(const _ChapterMarkerSeed(id: 'intro', startOffset: 0));
    }
    seeds.addAll(markers);

    final ranges = <ReaderChapterRangeData>[];
    for (int i = 0; i < seeds.length; i++) {
      final startOffset = seeds[i].startOffset;
      final endOffset = (i + 1 < seeds.length)
          ? seeds[i + 1].startOffset
          : content.length;
      final paragraphStart = _firstParagraphIndexAtOrAfter(
        paragraphs: paragraphs,
        offset: startOffset,
      );
      final paragraphEnd = _firstParagraphIndexAtOrAfter(
        paragraphs: paragraphs,
        offset: endOffset,
      );
      if (paragraphStart >= paragraphEnd) {
        continue;
      }
      ranges.add(
        ReaderChapterRangeData(
          id: seeds[i].id,
          paragraphStartIndex: paragraphStart,
          paragraphEndIndex: paragraphEnd,
        ),
      );
    }

    if (ranges.isEmpty) {
      return [
        ReaderChapterRangeData(
          id: 'root',
          paragraphStartIndex: 0,
          paragraphEndIndex: paragraphs.length,
        ),
      ];
    }
    return ranges;
  }

  List<_ChapterMarkerSeed> _collectChapterMarkers(String content) {
    final markers = <_ChapterMarkerSeed>[];
    int lineStart = 0;
    int chapterIndex = 1;

    while (lineStart <= content.length) {
      int lineEnd = content.indexOf('\n', lineStart);
      if (lineEnd == -1) {
        lineEnd = content.length;
      }
      final line = content.substring(lineStart, lineEnd);
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && _chapterHeadingPattern.hasMatch(trimmed)) {
        markers.add(
          _ChapterMarkerSeed(id: 'ch_$chapterIndex', startOffset: lineStart),
        );
        chapterIndex++;
      }
      if (lineEnd >= content.length) {
        break;
      }
      lineStart = lineEnd + 1;
    }

    return markers;
  }

  int _firstParagraphIndexAtOrAfter({
    required List<ReaderParagraphRangeData> paragraphs,
    required int offset,
  }) {
    int low = 0;
    int high = paragraphs.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (paragraphs[mid].start < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low.clamp(0, paragraphs.length);
  }

  String _stableHash(String value) {
    const int fnvOffsetBasis = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffsetBasis;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _ChapterMarkerSeed {
  const _ChapterMarkerSeed({required this.id, required this.startOffset});

  final String id;
  final int startOffset;
}
