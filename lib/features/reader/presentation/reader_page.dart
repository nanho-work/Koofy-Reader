import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/data/reader_settings_repository.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/data/reader_font_registry.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_bookmark_controller.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_layout_controller.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_progress_saver.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_search_controller.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_session_controller.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_app_bar_actions.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_content_switcher.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_dialogs.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_settings_sheet.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_visuals.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  static const int _doubleWindowBeforeParagraphs = 36;
  static const int _doubleWindowAfterParagraphs = 72;
  static const int _doubleWindowMinChars = 11000;
  static const int _doubleWindowMaxChars = 60000;
  static const int _previewPageCount = 10;

  late final ReaderSessionController _sessionController;
  final ReaderProgressSaver _progressSaver = ReaderProgressSaver();
  final ScrollController _scrollController = ScrollController();

  String _content = '';
  String? _errorText;
  bool _isBootstrapping = true;

  ReaderSettings _settings = ReaderSettings.defaults();
  double? _restoredRatio;
  int? _restoredContentOffset;
  bool _restoredScrollApplied = false;
  int _lastKnownContentOffset = 0;
  List<ReaderParagraphRange> _paragraphRanges = const <ReaderParagraphRange>[];
  List<ReaderChapterRange> _chapterRanges = const <ReaderChapterRange>[];

  Set<int> _bookmarks = <int>{};
  List<String> _searchHistory = <String>[];

  String _activeQuery = '';
  List<int> _queryOffsets = <int>[];
  int _queryCursor = -1;

  String? _singleLayoutSignature;
  TextPainter? _singleTextPainter;
  double _singleViewportHeight = 0;
  PaginatedText? _spreadPages;
  int _spreadIndex = 0;
  String? _spreadSignature;
  String? _activeSpreadSignature;
  int _spreadToken = 0;
  bool _isSpreadPaginating = false;
  bool _isDoubleActive = false;
  int? _pendingAnchorOffset;
  bool _forceSpreadAnchorTop = false;
  int _modeEpoch = 0;
  bool _hasInitializedMode = false;
  bool _isModeTransitioning = false;
  bool? _modeTransitionTarget;
  int? _pendingModeAnchorOffset;
  Timer? _modeTransitionDebounce;
  bool _isPersistingPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScrollChanged);
    _sessionController = ReaderSessionController(
      readerRepository: ref.read(readerRepositoryProvider),
      settingsRepository: ref.read(readerSettingsRepositoryProvider),
      bookRepository: ref.read(bookRepositoryProvider),
      paginationEngine: TextPaginationEngine(),
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScrollChanged);
    _progressSaver.cancel();
    _modeTransitionDebounce?.cancel();
    unawaited(_persistProgressNow(force: true));
    unawaited(WakelockPlus.disable());
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistProgressNow(force: true));
    }
  }

  Future<void> _bootstrap() async {
    try {
      final data = await _sessionController.bootstrap(widget.book);
      _settings = data.settings;
      _bookmarks = data.bookmarks;
      _searchHistory = data.searchHistory;
      _content = data.content;
      _indexContent(data.structureIndex);
      final fontNormalizationFuture = _normalizeAndLoadFont();
      _restoredRatio = data.progress?.positionRatio;
      _restoredContentOffset = _resolveStoredOffset(data.progress);
      _restoredScrollApplied = false;
      _lastKnownContentOffset = (_restoredContentOffset ?? 0).clamp(
        0,
        _content.length,
      );
      _tracePosition(
        'bootstrap_loaded',
        offset: _lastKnownContentOffset,
        details: 'hasProgress=${data.progress != null}',
      );

      await _applyWakelock();

      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
      });
      _deferRestoreScrollIfNeeded();
      unawaited(() async {
        final changed = await fontNormalizationFuture;
        if (!mounted || !changed) {
          return;
        }
        setState(() {
          _singleLayoutSignature = null;
          _singleTextPainter = null;
          _singleViewportHeight = 0;
          _spreadSignature = null;
          _activeSpreadSignature = null;
          _spreadToken++;
          _isSpreadPaginating = false;
          _restoredScrollApplied = false;
          if (_isDoubleActive) {
            _forceSpreadAnchorTop = true;
          }
        });
      }());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorText = '$error';
        _isBootstrapping = false;
      });
    }
  }

  Future<void> _applyWakelock() async {
    if (_settings.keepScreenOn) {
      await WakelockPlus.enable();
      return;
    }
    await WakelockPlus.disable();
  }

  ReaderPalette get _palette => resolveReaderPalette(_settings.backgroundMode);
  ReaderLayoutController get _layout =>
      ReaderLayoutController(settings: _settings);

  int _normalizeToLineStartOffset(int offset) {
    if (_content.isEmpty) {
      return 0;
    }
    var cursor = offset.clamp(0, _content.length);
    if (cursor >= _content.length && _content.isNotEmpty) {
      cursor = _content.length - 1;
    }
    while (cursor > 0 && _content.codeUnitAt(cursor - 1) != 0x0A) {
      cursor--;
    }
    return cursor.clamp(0, _content.length);
  }

  int _normalizeToVisualLineStartOffset(int offset) {
    final fallback = _normalizeToLineStartOffset(offset);
    final painter = _singleTextPainter;
    if (painter == null || _content.isEmpty) {
      return fallback;
    }
    var clamped = offset.clamp(0, _content.length);
    if (clamped >= _content.length && _content.isNotEmpty) {
      clamped = _content.length - 1;
    }
    final line = painter.getLineBoundary(TextPosition(offset: clamped));
    return line.start.clamp(0, _content.length);
  }

  Future<bool> _normalizeAndLoadFont() async {
    final registry = ref.read(readerFontRegistryProvider);
    final fonts = await registry.loadAvailableFonts();
    var changed = false;
    final exists = fonts.any((font) => font.key == _settings.fontKey);
    if (!exists) {
      changed = true;
      _settings = ReaderSettings.defaults().copyWith(
        backgroundMode: _settings.backgroundMode,
        pageLayoutMode: _settings.pageLayoutMode,
        fontSize: _settings.fontSize,
        lineHeight: _settings.lineHeight,
        horizontalPadding: _settings.horizontalPadding,
        keepScreenOn: _settings.keepScreenOn,
      );
    }
    await registry.ensureLoadedForKey(_settings.fontKey);
    return changed;
  }

  void _indexContent(ReaderStructureIndex? structureIndex) {
    final indexed = ReaderContentIndexer.fromContent(
      _content,
      structureIndex: structureIndex,
    );
    _paragraphRanges = indexed.paragraphRanges;
    _chapterRanges = indexed.chapterRanges;
  }

  int? _resolveStoredOffset(ReadingProgress? progress) {
    if (progress == null) {
      return null;
    }
    final fromAnchor = _offsetFromAnchor(progress.anchor);
    if (fromAnchor != null) {
      _tracePosition(
        'resolve_stored_offset_anchor',
        offset: fromAnchor,
        anchor: progress.anchor,
      );
      return fromAnchor.clamp(0, _content.length);
    }
    _tracePosition(
      'resolve_stored_offset_fallback',
      offset: progress.contentOffset,
      details: 'anchorMissingOrInvalid=true',
    );
    return progress.contentOffset.clamp(0, _content.length);
  }

  int _findParagraphIndexByOffset(int offset) {
    return ReaderContentIndexer.findParagraphIndexByOffset(
      _paragraphRanges,
      offset,
    );
  }

  ReadingAnchor _buildAnchorForOffset(int offset) {
    return ReaderContentIndexer.buildAnchorForOffset(
      offset: offset,
      contentLength: _content.length,
      paragraphRanges: _paragraphRanges,
      chapterRanges: _chapterRanges,
    );
  }

  int? _offsetFromAnchor(ReadingAnchor? anchor) {
    return ReaderContentIndexer.offsetFromAnchor(
      anchor: anchor,
      paragraphRanges: _paragraphRanges,
      chapterRanges: _chapterRanges,
    );
  }

  void _tracePosition(
    String event, {
    int? offset,
    ReadingAnchor? anchor,
    String? details,
  }) {
    if (!kDebugMode) {
      return;
    }
    final safeOffset = (offset ?? _lastKnownContentOffset).clamp(
      0,
      _content.length,
    );
    final safeAnchor = anchor ?? _buildAnchorForOffset(safeOffset);
    final spreadStart =
        (_spreadPages != null && _spreadPages!.ranges.isNotEmpty)
        ? _spreadPages!
              .ranges[_spreadIndex.clamp(0, _spreadPages!.length - 1)]
              .start
        : -1;
    final mode = _isDoubleActive ? 'double' : 'single';
    final suffix = details == null ? '' : ' details=$details';
    debugPrint(
      '[ReaderPos][$event] '
      'mode=$mode '
      'offset=$safeOffset '
      'anchor=${safeAnchor.chapterId}/${safeAnchor.paragraphIndex}/${safeAnchor.charOffset} '
      'pending=$_pendingAnchorOffset restored=$_restoredContentOffset '
      'last=$_lastKnownContentOffset spreadIndex=$_spreadIndex spreadStart=$spreadStart '
      'forceSpreadTop=$_forceSpreadAnchorTop modeEpoch=$_modeEpoch$suffix',
    );
  }

  TextStyle _readerTextStyle(ReaderPalette palette) {
    return TextStyle(
      color: palette.text,
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      fontFamily: _settings.fontFamily,
    );
  }

  double get _progressRatio {
    if (_content.isEmpty) return 0;
    return (_currentContentOffset() / _content.length).clamp(0.0, 1.0);
  }

  void _ensureSingleTextLayout({
    required Size viewport,
    required TextStyle style,
  }) {
    if (_content.isEmpty || viewport.width <= 0 || viewport.height <= 0) {
      return;
    }
    final maxWidth = (viewport.width - (_settings.horizontalPadding * 2)).clamp(
      80.0,
      10000.0,
    );
    final signature = [
      _content.length,
      maxWidth.toStringAsFixed(2),
      style.fontFamily ?? '',
      style.fontSize?.toStringAsFixed(2) ?? '',
      style.height?.toStringAsFixed(3) ?? '',
      _settings.horizontalPadding.toStringAsFixed(2),
    ].join('|');
    if (_singleLayoutSignature == signature && _singleTextPainter != null) {
      _singleViewportHeight = viewport.height;
      return;
    }

    final painter = TextPainter(
      text: TextSpan(text: _content, style: style),
      strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    _singleTextPainter = painter;
    _singleLayoutSignature = signature;
    _singleViewportHeight = viewport.height;
  }

  int _currentSingleContentOffset() {
    if (_content.isEmpty) return 0;
    final painter = _singleTextPainter;
    if (painter == null || !_scrollController.hasClients) {
      return _lastKnownContentOffset.clamp(0, _content.length);
    }
    final localY = (_scrollController.offset - readerVerticalPadding).clamp(
      0.0,
      painter.height,
    );
    final position = painter.getPositionForOffset(Offset(0, localY));
    return _normalizeToVisualLineStartOffset(
      position.offset.clamp(0, _content.length),
    );
  }

  double _singleScrollOffsetForContentOffset(int contentOffset) {
    final painter = _singleTextPainter;
    if (painter == null || _content.isEmpty) {
      return 0;
    }
    final clampedOffset = _normalizeToVisualLineStartOffset(contentOffset);
    final caretOffset = painter.getOffsetForCaret(
      TextPosition(offset: clampedOffset),
      Rect.zero,
    );
    final raw = (caretOffset.dy + readerVerticalPadding).clamp(
      0.0,
      double.infinity,
    );

    if (_scrollController.hasClients) {
      return raw.clamp(0.0, _scrollController.position.maxScrollExtent);
    }

    final estimatedExtent =
        painter.height +
        readerContentBottomInset +
        (readerVerticalPadding * 2) -
        _singleViewportHeight;
    final estimatedMax = estimatedExtent > 0 ? estimatedExtent : 0.0;
    return raw.clamp(0.0, estimatedMax);
  }

  int _currentContentOffset() {
    if (_content.isEmpty) return 0;
    if (_isDoubleActive && _spreadPages != null && _spreadPages!.length > 0) {
      final safeIndex = _spreadIndex.clamp(0, _spreadPages!.length - 1);
      return _spreadPages!.ranges[safeIndex].start.clamp(
        0,
        _spreadPages!.source.length,
      );
    }
    return _currentSingleContentOffset();
  }

  int _resolveStableAnchorOffset() {
    if (!_isDoubleActive) {
      return _currentSingleContentOffset().clamp(0, _content.length);
    }
    final pages = _spreadPages;
    if (pages != null && pages.length > 0) {
      final safeIndex = _spreadIndex.clamp(0, pages.length - 1);
      return pages.ranges[safeIndex].start.clamp(0, pages.source.length);
    }
    if (_pendingAnchorOffset != null) {
      return _pendingAnchorOffset!.clamp(0, _content.length);
    }
    if (_restoredContentOffset != null) {
      return _restoredContentOffset!.clamp(0, _content.length);
    }
    return _lastKnownContentOffset.clamp(0, _content.length);
  }

  bool get _isCurrentBookmarked {
    final anchor = _currentContentOffset();
    return ReaderBookmarkController.hasNearbyBookmark(
      _bookmarks,
      anchor: anchor,
    );
  }

  void _onScrollChanged() {
    if (_isBootstrapping || _content.isEmpty || _isModeTransitioning) return;
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
    _scheduleProgressSave();
  }

  void _deferRestoreScrollIfNeeded() {
    if (_restoredScrollApplied) {
      return;
    }
    final restoredOffsetRaw =
        _restoredContentOffset ??
        (_restoredRatio == null || _content.isEmpty
            ? null
            : ((_restoredRatio!.clamp(0.0, 1.0)) * _content.length).round());
    if (restoredOffsetRaw == null) {
      _restoredScrollApplied = true;
      return;
    }
    if (_isDoubleActive) {
      return;
    }

    var attempts = 0;
    const maxAttempts = 16;

    void attemptRestore() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _restoredScrollApplied) {
          return;
        }
        if (!_scrollController.hasClients) {
          attempts += 1;
          if (attempts < maxAttempts) {
            attemptRestore();
            return;
          }
          _restoredScrollApplied = true;
          return;
        }
        if (_singleTextPainter == null) {
          attempts += 1;
          if (attempts < maxAttempts) {
            attemptRestore();
            return;
          }
          _restoredScrollApplied = true;
          return;
        }
        final restoredOffset = _normalizeToVisualLineStartOffset(
          restoredOffsetRaw,
        );
        final target = _singleScrollOffsetForContentOffset(restoredOffset);
        _scrollController.jumpTo(target);
        _lastKnownContentOffset = _currentContentOffset().clamp(
          0,
          _content.length,
        );
        _tracePosition(
          'restore_single_applied',
          offset: _lastKnownContentOffset,
          details: 'targetPx=${target.toStringAsFixed(1)}',
        );
        _restoredScrollApplied = true;
      });
    }

    attemptRestore();
  }

  Future<void> _persistProgressNow({bool force = false}) async {
    if (_content.isEmpty || (_isModeTransitioning && !force)) {
      return;
    }
    final ratio = _progressRatio.clamp(0.0, 1.0);
    final rawOffset = _currentContentOffset().clamp(0, _content.length);
    final contentOffset = _isDoubleActive
        ? _normalizeToLineStartOffset(rawOffset)
        : _normalizeToVisualLineStartOffset(rawOffset);
    final anchor = _buildAnchorForOffset(contentOffset);
    final isSingleActive = !_isDoubleActive;
    final offsetPx = isSingleActive && _scrollController.hasClients
        ? _scrollController.offset
        : null;
    final maxExtentPx = isSingleActive && _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : null;
    _tracePosition(
      'save_progress',
      offset: contentOffset,
      anchor: anchor,
      details: 'force=$force ratio=${ratio.toStringAsFixed(4)}',
    );

    final progress = ReadingProgress(
      bookId: widget.book.id,
      positionRatio: ratio,
      contentOffset: contentOffset,
      updatedAt: DateTime.now(),
      scrollOffsetPx: offsetPx,
      scrollMaxExtentPx: maxExtentPx,
      anchor: anchor,
    );
    await _sessionController.saveProgress(progress);
  }

  void _scheduleProgressSave() {
    if (_isModeTransitioning) {
      return;
    }
    _progressSaver.schedule(_persistProgressNow);
  }

  Future<void> _jumpToContentOffset(int offset, {bool animate = true}) async {
    if (_content.isEmpty) return;
    final clampedOffset = offset.clamp(0, _content.length);
    final targetOffset = _isDoubleActive
        ? _normalizeToLineStartOffset(clampedOffset)
        : _normalizeToVisualLineStartOffset(clampedOffset);
    final ratio = (targetOffset / _content.length).clamp(0.0, 1.0);
    _tracePosition(
      'jump_request',
      offset: targetOffset,
      details: 'mode=${_isDoubleActive ? 'double' : 'single'}',
    );

    _restoredContentOffset = targetOffset;
    _restoredRatio = ratio;
    _lastKnownContentOffset = targetOffset;

    if (_isDoubleActive) {
      _forceSpreadAnchorTop = true;
      _requestSpreadWindowRepagination(targetOffset);
      _tracePosition(
        'jump_request_double_repaginate',
        offset: targetOffset,
        details: 'forceSpreadTop=true',
      );
      return;
    }

    if (_singleTextPainter == null || !_scrollController.hasClients) {
      _pendingAnchorOffset = targetOffset;
      _restoredScrollApplied = false;
      _tracePosition(
        'jump_request_single_deferred',
        offset: targetOffset,
        details: 'layoutNotReady=true',
      );
      return;
    }
    _restoredScrollApplied = true;
    final target = _singleScrollOffsetForContentOffset(targetOffset);
    if (animate) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
    _tracePosition(
      'jump_applied_single',
      offset: _lastKnownContentOffset,
      details: 'targetPx=${target.toStringAsFixed(1)}',
    );
  }

  Future<void> _handlePopInvoked(bool didPop, Object? result) async {
    if (didPop || _isPersistingPop) {
      return;
    }
    _isPersistingPop = true;
    try {
      await _persistProgressNow(force: true);
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } finally {
      _isPersistingPop = false;
    }
  }

  void _goSpread({required bool forward}) {
    if (_isSpreadPaginating) {
      return;
    }
    final pages = _spreadPages;
    if (pages == null || pages.length == 0) {
      return;
    }
    final next = _spreadIndex + (forward ? 2 : -2);
    final clamped = _clampSpreadStartIndex(next, pages.length);
    if (clamped == _spreadIndex) {
      if (forward &&
          _spreadIndex >= pages.length - 2 &&
          pages.ranges.last.end < _content.length) {
        final rightIndex = (_spreadIndex + 1).clamp(0, pages.length - 1);
        final nextAnchor = pages.ranges[rightIndex].end.clamp(
          0,
          _content.length,
        );
        _forceSpreadAnchorTop = true;
        _requestSpreadWindowRepagination(nextAnchor);
      } else if (!forward &&
          _spreadIndex == 0 &&
          pages.ranges.first.start > 0) {
        final prevAnchor = (pages.ranges.first.start - 1).clamp(
          0,
          _content.length,
        );
        _forceSpreadAnchorTop = true;
        _requestSpreadWindowRepagination(prevAnchor);
      }
      return;
    }
    setState(() {
      _spreadIndex = clamped;
      _pendingAnchorOffset = null;
      _forceSpreadAnchorTop = false;
    });
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
    _scheduleProgressSave();
  }

  int _findPageIndexByOffset(PaginatedText pages, int offset) {
    int low = 0;
    int high = pages.ranges.length - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      final end = pages.ranges[mid].end;
      if (offset < end) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low.clamp(0, pages.ranges.length - 1);
  }

  int _mapSpreadIndexByOffset(PaginatedText pages, int offset) {
    if (pages.length <= 1) return 0;
    final raw = _findPageIndexByOffset(
      pages,
      offset.clamp(0, pages.source.length),
    );
    final aligned = raw.isOdd ? raw - 1 : raw;
    return _clampSpreadStartIndex(aligned, pages.length);
  }

  bool _containsOffset(PaginatedText pages, int offset) {
    if (pages.length == 0 || pages.ranges.isEmpty) {
      return false;
    }
    final normalized = offset.clamp(0, _content.length);
    final start = pages.ranges.first.start;
    final end = pages.ranges.last.end;
    if (normalized >= _content.length) {
      return end >= _content.length;
    }
    return normalized >= start && normalized < end;
  }

  _PaginationWindow _buildPaginationWindow({
    required int anchorOffset,
    int? forceStartOffset,
  }) {
    if (_content.isEmpty || _paragraphRanges.isEmpty) {
      return _PaginationWindow(
        startOffset: 0,
        endOffset: _content.length,
        content: _content,
      );
    }

    if (forceStartOffset != null) {
      int startOffset = _normalizeToLineStartOffset(
        forceStartOffset,
      ).clamp(0, _content.length);
      if (startOffset >= _content.length && _content.isNotEmpty) {
        startOffset = _content.length - 1;
      }
      int endOffset = (startOffset + _doubleWindowMaxChars).clamp(
        startOffset,
        _content.length,
      );
      final minimumEnd = (startOffset + _doubleWindowMinChars).clamp(
        startOffset,
        _content.length,
      );
      if (endOffset < minimumEnd) {
        endOffset = minimumEnd;
      }
      while (endOffset < _content.length &&
          _content.codeUnitAt(endOffset) != 0x0A) {
        endOffset++;
      }
      if (endOffset <= startOffset) {
        return _PaginationWindow(
          startOffset: 0,
          endOffset: _content.length,
          content: _content,
        );
      }
      return _PaginationWindow(
        startOffset: startOffset,
        endOffset: endOffset,
        content: _content.substring(startOffset, endOffset),
      );
    }

    final clampedAnchor = anchorOffset.clamp(0, _content.length);
    final centerParagraph = _findParagraphIndexByOffset(clampedAnchor);
    final before = _doubleWindowBeforeParagraphs;
    final after = _doubleWindowAfterParagraphs;
    final minChars = _doubleWindowMinChars;
    final maxChars = _doubleWindowMaxChars;

    int startParagraph = (centerParagraph - before).clamp(
      0,
      _paragraphRanges.length - 1,
    );
    int endParagraph = (centerParagraph + after).clamp(
      0,
      _paragraphRanges.length - 1,
    );
    int startOffset = _paragraphRanges[startParagraph].start;
    int endOffset = _paragraphRanges[endParagraph].end;

    while (startOffset > 0 && _content.codeUnitAt(startOffset - 1) == 0x0A) {
      startOffset--;
    }
    while (endOffset < _content.length &&
        _content.codeUnitAt(endOffset) == 0x0A) {
      endOffset++;
    }

    int span = endOffset - startOffset;
    if (span < minChars && _content.length > minChars) {
      final desiredStart = (clampedAnchor - (minChars ~/ 2)).clamp(
        0,
        _content.length,
      );
      final desiredEnd = (desiredStart + minChars).clamp(0, _content.length);
      startOffset = desiredStart;
      endOffset = desiredEnd;
      while (startOffset > 0 && _content.codeUnitAt(startOffset - 1) != 0x0A) {
        startOffset--;
      }
      while (endOffset < _content.length &&
          _content.codeUnitAt(endOffset) != 0x0A) {
        endOffset++;
      }
    }

    span = endOffset - startOffset;
    if (span > maxChars) {
      final desiredStart = (clampedAnchor - (maxChars ~/ 2)).clamp(
        0,
        _content.length,
      );
      final desiredEnd = (desiredStart + maxChars).clamp(0, _content.length);
      startOffset = desiredStart;
      endOffset = desiredEnd;
      while (startOffset > 0 && _content.codeUnitAt(startOffset - 1) != 0x0A) {
        startOffset--;
      }
      while (endOffset < _content.length &&
          _content.codeUnitAt(endOffset) != 0x0A) {
        endOffset++;
      }
    }

    if (endOffset <= startOffset) {
      return _PaginationWindow(
        startOffset: 0,
        endOffset: _content.length,
        content: _content,
      );
    }
    return _PaginationWindow(
      startOffset: startOffset,
      endOffset: endOffset,
      content: _content.substring(startOffset, endOffset),
    );
  }

  PaginatedText _toGlobalPaginatedText({
    required PaginatedText localPages,
    required int windowStartOffset,
  }) {
    if (localPages.length == 0 || localPages.ranges.isEmpty) {
      return PaginatedText(
        source: _content,
        ranges: const [TextPageRange(start: 0, end: 0)],
      );
    }

    final globalRanges = <TextPageRange>[];
    for (final range in localPages.ranges) {
      final start = (windowStartOffset + range.start).clamp(0, _content.length);
      final end = (windowStartOffset + range.end).clamp(start, _content.length);
      if (end <= start) {
        continue;
      }
      globalRanges.add(TextPageRange(start: start, end: end));
    }

    if (globalRanges.isEmpty) {
      final start = windowStartOffset.clamp(0, _content.length);
      final end = (start + 1).clamp(start, _content.length);
      globalRanges.add(TextPageRange(start: start, end: end));
    }

    return PaginatedText(source: _content, ranges: globalRanges);
  }

  void _requestSpreadWindowRepagination(int anchorOffset) {
    _pendingAnchorOffset = _normalizeToLineStartOffset(
      anchorOffset.clamp(0, _content.length),
    );
    _spreadSignature = null;
    _activeSpreadSignature = null;
    _spreadToken++;
    _tracePosition(
      'spread_repaginate_requested',
      offset: _pendingAnchorOffset,
      details: 'spreadToken=$_spreadToken',
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleModeTransition({
    required bool targetMode,
    required int anchorOffset,
  }) {
    final normalizedIncoming = targetMode
        ? _normalizeToLineStartOffset(anchorOffset)
        : _normalizeToVisualLineStartOffset(anchorOffset);
    final clampedAnchor = normalizedIncoming.clamp(0, _content.length);
    _tracePosition(
      'mode_transition_schedule',
      offset: clampedAnchor,
      details: 'target=${targetMode ? 'double' : 'single'}',
    );

    _modeEpoch++;
    _pendingModeAnchorOffset = clampedAnchor;
    _modeTransitionTarget = targetMode;
    _isModeTransitioning = true;
    // Invalidate any in-flight spread pagination so stale callbacks
    // cannot overwrite the position during mode transitions.
    _spreadToken++;
    _activeSpreadSignature = null;
    _spreadSignature = null;
    if (targetMode) {
      // Prevent stale spread pages from flashing while transitioning.
      _spreadPages = null;
      _spreadIndex = 0;
      _isSpreadPaginating = false;
    }

    void applyTransitionNow() {
      if (!mounted) return;
      final applyMode = _modeTransitionTarget ?? targetMode;
      final applyAnchor = (_pendingModeAnchorOffset ?? clampedAnchor).clamp(
        0,
        _content.length,
      );
      setState(() {
        _isDoubleActive = applyMode;
        _pendingAnchorOffset = applyAnchor;
        if (applyMode) {
          _forceSpreadAnchorTop = true;
          _spreadPages = null;
          _spreadIndex = 0;
          _spreadSignature = null;
          _activeSpreadSignature = null;
        } else {
          _isSpreadPaginating = false;
          _forceSpreadAnchorTop = false;
          _spreadPages = null;
          _spreadIndex = 0;
          _spreadSignature = null;
          _activeSpreadSignature = null;
        }
        _isModeTransitioning = false;
      });
      _tracePosition(
        'mode_transition_applied',
        offset: applyAnchor,
        details: 'applied=${applyMode ? 'double' : 'single'}',
      );
      _modeTransitionTarget = null;
      _pendingModeAnchorOffset = null;
    }

    _modeTransitionDebounce?.cancel();
    if (!targetMode) {
      applyTransitionNow();
      return;
    }
    _modeTransitionDebounce = Timer(
      const Duration(milliseconds: 90),
      applyTransitionNow,
    );
  }

  int _clampSpreadStartIndex(int index, int totalPages) {
    if (totalPages <= 1) {
      return 0;
    }
    final maxRaw = totalPages - 1;
    final maxLeft = maxRaw.isOdd ? maxRaw - 1 : maxRaw;
    final clamped = index.clamp(0, maxLeft);
    return clamped.isOdd ? clamped - 1 : clamped;
  }

  Future<void> _goSingleScrollByViewport({required bool forward}) async {
    if (!_scrollController.hasClients) {
      return;
    }
    final viewport = _singleViewportHeight > 0
        ? _singleViewportHeight
        : _scrollController.position.viewportDimension;
    final delta = (viewport * 0.88).clamp(60.0, 1200.0);
    final target = (_scrollController.offset + (forward ? delta : -delta))
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
    _scheduleProgressSave();
  }

  void _ensureSpreadPagination({
    required Size viewport,
    required MediaQueryData mediaQueryData,
    required TextStyle style,
  }) {
    if (_content.isEmpty) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;
    // Do not paginate spread pages while transitioning to single mode.
    if (_isModeTransitioning && _modeTransitionTarget == false) {
      return;
    }

    final signature = _layout.paginationSignature(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    final signatureChanged =
        _spreadSignature != null && signature != _spreadSignature;
    final shouldForceSpreadAnchorTop =
        _forceSpreadAnchorTop ||
        _pendingAnchorOffset != null ||
        signatureChanged;
    if (!shouldForceSpreadAnchorTop &&
        signature == _spreadSignature &&
        _spreadPages != null) {
      if (_pendingAnchorOffset != null) {
        final pending = _pendingAnchorOffset!.clamp(0, _content.length);
        if (_containsOffset(_spreadPages!, pending)) {
          final mapped = _mapSpreadIndexByOffset(_spreadPages!, pending);
          _pendingAnchorOffset = null;
          setState(() {
            _spreadIndex = mapped;
          });
        } else {
          _spreadSignature = null;
        }
      }
      if (signature == _spreadSignature) {
        return;
      }
    }
    if (signature == _activeSpreadSignature) {
      return;
    }

    _activeSpreadSignature = signature;
    final token = ++_spreadToken;
    final modeEpochAtRequest = _modeEpoch;
    final requestedAnchor = _normalizeToLineStartOffset(
      (_pendingAnchorOffset ?? _resolveStableAnchorOffset()).clamp(
        0,
        _content.length,
      ),
    );
    _tracePosition(
      'spread_paginate_start',
      offset: requestedAnchor,
      details:
          'signature=$signature forceTop=$shouldForceSpreadAnchorTop token=$token',
    );
    final paginationWindow = _buildPaginationWindow(
      anchorOffset: requestedAnchor,
      forceStartOffset: shouldForceSpreadAnchorTop ? requestedAnchor : null,
    );
    setState(() {
      _isSpreadPaginating = true;
    });

    final textArea = _layout.textAreaForPagination(
      viewport,
      mediaQueryData: mediaQueryData,
    );

    unawaited(() async {
      try {
        final result = await _sessionController.paginate(
          content: paginationWindow.content,
          textArea: textArea,
          textStyle: style,
          previewPageCount: _previewPageCount,
          onPreviewReady: (preview) {
            if (!mounted ||
                token != _spreadToken ||
                _modeEpoch != modeEpochAtRequest ||
                !_isDoubleActive) {
              return;
            }
            final previewGlobal = _toGlobalPaginatedText(
              localPages: preview,
              windowStartOffset: paginationWindow.startOffset,
            );
            final previewMapped = shouldForceSpreadAnchorTop
                ? 0
                : _mapSpreadIndexByOffset(
                    previewGlobal,
                    (_pendingAnchorOffset ?? requestedAnchor).clamp(
                      0,
                      _content.length,
                    ),
                  );
            setState(() {
              _spreadPages = previewGlobal;
              _spreadIndex = previewMapped;
            });
            _lastKnownContentOffset = shouldForceSpreadAnchorTop
                ? requestedAnchor
                : previewGlobal.ranges[previewMapped].start.clamp(
                    0,
                    _content.length,
                  );
            _tracePosition(
              'spread_paginate_preview',
              offset: _lastKnownContentOffset,
              details:
                  'mapped=$previewMapped forceTop=$shouldForceSpreadAnchorTop',
            );
          },
        );
        if (!mounted ||
            token != _spreadToken ||
            _modeEpoch != modeEpochAtRequest ||
            !_isDoubleActive) {
          return;
        }
        final globalPages = _toGlobalPaginatedText(
          localPages: result.pages,
          windowStartOffset: paginationWindow.startOffset,
        );
        final mapped = shouldForceSpreadAnchorTop
            ? 0
            : _mapSpreadIndexByOffset(
                globalPages,
                (_pendingAnchorOffset ?? requestedAnchor).clamp(
                  0,
                  _content.length,
                ),
              );
        setState(() {
          _spreadPages = globalPages;
          _spreadIndex = mapped;
          _spreadSignature = signature;
          _isSpreadPaginating = false;
        });
        _lastKnownContentOffset = shouldForceSpreadAnchorTop
            ? requestedAnchor
            : globalPages.ranges[mapped].start.clamp(0, _content.length);
        _pendingAnchorOffset = null;
        _forceSpreadAnchorTop = false;
        _tracePosition(
          'spread_paginate_done',
          offset: _lastKnownContentOffset,
          details: 'mapped=$mapped forceTop=$shouldForceSpreadAnchorTop',
        );
      } catch (_) {
        if (!mounted || token != _spreadToken) return;
        setState(() {
          _isSpreadPaginating = false;
        });
        _forceSpreadAnchorTop = false;
        _tracePosition(
          'spread_paginate_error',
          offset: requestedAnchor,
          details: 'token=$token',
        );
      } finally {
        if (_activeSpreadSignature == signature) {
          _activeSpreadSignature = null;
        }
      }
    }());
  }

  void _toggleCurrentBookmark() {
    if (_content.isEmpty) return;
    final anchor = _currentContentOffset();

    setState(() {
      _bookmarks = ReaderBookmarkController.toggleNearbyBookmark(
        _bookmarks,
        anchor: anchor,
      );
    });
    unawaited(_sessionController.saveBookmarks(widget.book.id, _bookmarks));
  }

  Future<void> _openBookmarksSheet() async {
    if (_bookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('등록된 북마크가 없습니다.')));
      return;
    }

    final target = await showReaderBookmarksSheet(
      context: context,
      bookmarks: _bookmarks,
    );

    if (target != null) {
      await _jumpToContentOffset(target);
    }
  }

  Future<void> _openSearchDialog() async {
    final query = await showReaderSearchDialog(
      context: context,
      initialQuery: _activeQuery,
      history: _searchHistory,
    );

    if (query == null) {
      return;
    }
    _applySearchQuery(query);
  }

  void _applySearchQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _activeQuery = '';
        _queryOffsets = <int>[];
        _queryCursor = -1;
      });
      return;
    }

    final offsets = ReaderSearchController.findQueryOffsets(
      source: _content,
      query: trimmed,
    );
    final history = ReaderSearchController.normalizeHistory([
      trimmed,
      ..._searchHistory,
    ]);

    setState(() {
      _activeQuery = trimmed;
      _queryOffsets = offsets;
      _queryCursor = offsets.isEmpty ? -1 : 0;
      _searchHistory = history;
    });

    unawaited(_sessionController.saveSearchHistory(history));

    if (offsets.isNotEmpty) {
      unawaited(_jumpToContentOffset(offsets.first));
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('검색 결과가 없습니다.')));
    }
  }

  void _moveQueryCursor(int delta) {
    if (_queryOffsets.isEmpty) {
      return;
    }
    final normalized = ReaderSearchController.moveCursor(
      current: _queryCursor,
      delta: delta,
      length: _queryOffsets.length,
    );

    setState(() {
      _queryCursor = normalized;
    });
    unawaited(_jumpToContentOffset(_queryOffsets[normalized]));
  }

  Future<void> _openReaderSettingsSheet() async {
    final fontItems = await ref
        .read(readerFontRegistryProvider)
        .loadAvailableFonts();
    if (!mounted) {
      return;
    }
    final result = await showReaderSettingsSheet(
      context: context,
      initialSettings: _settings,
      normalFontSize: readerFontSizeNormal,
      largeFontSize: readerFontSizeLarge,
      fontItems: fontItems,
    );

    if (result == null) {
      return;
    }

    final changed = result.toRaw() != _settings.toRaw();
    if (!changed) {
      return;
    }

    await ref
        .read(readerFontRegistryProvider)
        .ensureLoadedForKey(result.fontKey);

    final currentOffset = _resolveStableAnchorOffset().clamp(
      0,
      _content.length,
    );
    final currentAnchor = _buildAnchorForOffset(currentOffset);
    final restoredOffset =
        _offsetFromAnchor(currentAnchor)?.clamp(0, _content.length) ??
        currentOffset;
    setState(() {
      _settings = result;
      _pendingAnchorOffset = restoredOffset;
      _restoredContentOffset = restoredOffset;
      _restoredRatio = _content.isEmpty
          ? 0.0
          : (restoredOffset / _content.length).clamp(0.0, 1.0);
      _lastKnownContentOffset = restoredOffset;
      _singleLayoutSignature = null;
      _singleTextPainter = null;
      _singleViewportHeight = 0;
      _spreadSignature = null;
      _activeSpreadSignature = null;
      _spreadToken++;
      _isSpreadPaginating = false;
      _modeTransitionDebounce?.cancel();
      _isModeTransitioning = false;
      _modeTransitionTarget = null;
      _pendingModeAnchorOffset = null;
      if (_isDoubleActive) {
        _forceSpreadAnchorTop = true;
      }
      _restoredScrollApplied = false;
    });

    await _sessionController.saveSettings(result);
    await _applyWakelock();
    _scheduleProgressSave();
  }

  void _handleTapNavigation({
    required TapUpDetails details,
    required BoxConstraints constraints,
    required bool doubleMode,
  }) {
    if (doubleMode && _isSpreadPaginating) {
      return;
    }
    final action = _layout.resolveTapAction(
      dx: details.localPosition.dx,
      width: constraints.maxWidth,
    );
    switch (action) {
      case ReaderTapAction.previous:
        if (doubleMode) {
          _goSpread(forward: false);
        } else {
          unawaited(_goSingleScrollByViewport(forward: false));
        }
        break;
      case ReaderTapAction.next:
        if (doubleMode) {
          _goSpread(forward: true);
        } else {
          unawaited(_goSingleScrollByViewport(forward: true));
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: _handlePopInvoked,
      child: Scaffold(
        backgroundColor: palette.background,
        appBar: AppBar(
          backgroundColor: palette.panel,
          title: Text(widget.book.title),
          actions: [
            ReaderAppBarActions(
              hasQueryMatches: _queryOffsets.isNotEmpty,
              isCurrentBookmarked: _isCurrentBookmarked,
              onPrevQuery: () => _moveQueryCursor(-1),
              onNextQuery: () => _moveQueryCursor(1),
              onSearch: _openSearchDialog,
              onToggleBookmark: _toggleCurrentBookmark,
              onOpenBookmarks: _openBookmarksSheet,
              onOpenSettings: _openReaderSettingsSheet,
            ),
          ],
        ),
        body: _buildBody(palette),
        bottomNavigationBar: const SafeArea(child: AdFooterWidget()),
      ),
    );
  }

  Widget _buildBody(ReaderPalette palette) {
    if (_isBootstrapping) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorText != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '책 본문을 열 수 없습니다.\n$_errorText',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_content.trim().isEmpty) {
      return const Center(child: Text('본문이 비어 있습니다.'));
    }

    final style = _readerTextStyle(palette);

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final mediaQueryData = MediaQuery.of(context);
        final requestedDoubleMode = _layout.isDoublePageMode(
          viewport,
          mediaQueryData: mediaQueryData,
        );
        if (!_hasInitializedMode) {
          _hasInitializedMode = true;
          _isDoubleActive = requestedDoubleMode;
        } else if (requestedDoubleMode != _isDoubleActive) {
          _scheduleModeTransition(
            targetMode: requestedDoubleMode,
            anchorOffset: _resolveStableAnchorOffset(),
          );
        }
        final doubleMode = _isDoubleActive;
        _ensureSingleTextLayout(viewport: viewport, style: style);

        if (doubleMode) {
          if (!_restoredScrollApplied &&
              (_restoredContentOffset != null || _restoredRatio != null)) {
            _pendingAnchorOffset = _restoredContentOffset?.clamp(
              0,
              _content.length,
            );
            _pendingAnchorOffset ??=
                ((_restoredRatio!.clamp(0.0, 1.0)) * _content.length).round();
            _forceSpreadAnchorTop = true;
            _tracePosition(
              'double_restore_pending_set',
              offset: _pendingAnchorOffset,
              details: 'fromProgress=true',
            );
            _restoredScrollApplied = true;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_isDoubleActive) return;
            _ensureSpreadPagination(
              viewport: viewport,
              mediaQueryData: mediaQueryData,
              style: style,
            );
          });
        } else {
          _deferRestoreScrollIfNeeded();
          if (_pendingAnchorOffset != null) {
            final target = _pendingAnchorOffset!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _isDoubleActive) return;
              _pendingAnchorOffset = null;
              unawaited(_jumpToContentOffset(target, animate: false));
            });
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) => _handleTapNavigation(
            details: details,
            constraints: constraints,
            doubleMode: doubleMode,
          ),
          child: ReaderContentSwitcher(
            doubleMode: doubleMode,
            singleContent: _content,
            style: style,
            palette: palette,
            horizontalPadding: _settings.horizontalPadding,
            scrollController: _scrollController,
            spreadPages: _spreadPages,
            spreadIndex: _spreadIndex,
            isSpreadPaginating: _isSpreadPaginating,
          ),
        );
      },
    );
  }
}

class _PaginationWindow {
  const _PaginationWindow({
    required this.startOffset,
    required this.endOffset,
    required this.content,
  });

  final int startOffset;
  final int endOffset;
  final String content;
}
