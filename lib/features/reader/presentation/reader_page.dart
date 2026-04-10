import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/data/reader_settings_repository.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_bookmark_controller.dart';
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

  Set<int> _bookmarks = <int>{};
  List<String> _searchHistory = <String>[];

  String _activeQuery = '';
  List<int> _queryOffsets = <int>[];
  int _queryCursor = -1;

  PaginatedText? _singlePages;
  int _singleIndex = 0;
  String? _singleSignature;
  String? _activeSingleSignature;
  int _singleToken = 0;
  bool _isSinglePaginating = false;
  double _singlePageExtent = 1;
  PaginatedText? _spreadPages;
  int _spreadIndex = 0;
  String? _spreadSignature;
  String? _activeSpreadSignature;
  int _spreadToken = 0;
  bool _isSpreadPaginating = false;
  bool _isDoubleActive = false;
  int? _pendingAnchorOffset;

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
    unawaited(_persistProgressNow());
    unawaited(WakelockPlus.disable());
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistProgressNow());
    }
  }

  Future<void> _bootstrap() async {
    try {
      final data = await _sessionController.bootstrap(widget.book);
      _settings = data.settings;
      _bookmarks = data.bookmarks;
      _searchHistory = data.searchHistory;
      _content = data.content;
      _restoredRatio = data.progress?.positionRatio;
      _restoredContentOffset = data.progress?.contentOffset;
      _restoredScrollApplied = false;
      _lastKnownContentOffset = (data.progress?.contentOffset ?? 0).clamp(
        0,
        _content.length,
      );

      await _applyWakelock();

      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
      });
      _deferRestoreScrollIfNeeded();
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

  int _currentSinglePageIndex() {
    final pages = _singlePages;
    if (pages == null || pages.length == 0) {
      return 0;
    }
    if (_scrollController.hasClients && _singlePageExtent > 0) {
      final raw = (_scrollController.offset / _singlePageExtent).floor();
      return raw.clamp(0, pages.length - 1);
    }
    return _singleIndex.clamp(0, pages.length - 1);
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
    final pages = _singlePages;
    if (pages != null && pages.length > 0) {
      final safeIndex = _currentSinglePageIndex();
      return pages.ranges[safeIndex].start.clamp(0, pages.source.length);
    }
    return _lastKnownContentOffset.clamp(0, _content.length);
  }

  int _resolveStableAnchorOffset() {
    if (!_isDoubleActive) {
      final singlePages = _singlePages;
      if (singlePages != null && singlePages.length > 0) {
        final safeIndex = _currentSinglePageIndex();
        return singlePages.ranges[safeIndex].start.clamp(
          0,
          singlePages.source.length,
        );
      }
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
    if (_isBootstrapping || _content.isEmpty) return;
    if (!_isDoubleActive && _singlePages != null && _singlePages!.length > 0) {
      _singleIndex = _currentSinglePageIndex();
    }
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
    _scheduleProgressSave();
  }

  void _deferRestoreScrollIfNeeded() {
    if (_restoredScrollApplied) {
      return;
    }
    final restoredOffset =
        _restoredContentOffset ??
        (_restoredRatio == null || _content.isEmpty
            ? null
            : ((_restoredRatio!.clamp(0.0, 1.0)) * _content.length).round());
    if (restoredOffset == null) {
      _restoredScrollApplied = true;
      return;
    }
    final pages = _singlePages;
    if (_isDoubleActive || pages == null || pages.length == 0) {
      return;
    }

    var attempts = 0;
    const maxAttempts = 12;

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
        if (_singlePageExtent <= 0) {
          // ListView may need additional frames before content extent is ready.
          attempts += 1;
          if (attempts < maxAttempts) {
            attemptRestore();
            return;
          }
          // Bail out safely if extent never becomes ready.
          _restoredScrollApplied = true;
          return;
        }
        final mapped = _findPageIndexByOffset(pages, restoredOffset);
        _singleIndex = mapped;
        final target = (_singlePageExtent * mapped).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
        _lastKnownContentOffset = _currentContentOffset().clamp(
          0,
          _content.length,
        );
        _restoredScrollApplied = true;
      });
    }

    attemptRestore();
  }

  Future<void> _persistProgressNow() async {
    if (_content.isEmpty) {
      return;
    }
    final ratio = _progressRatio.clamp(0.0, 1.0);
    final contentOffset = _currentContentOffset().clamp(0, _content.length);
    final isSingleActive = !_isDoubleActive;
    final offsetPx = isSingleActive && _scrollController.hasClients
        ? _scrollController.offset
        : null;
    final maxExtentPx = isSingleActive && _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : null;

    final progress = ReadingProgress(
      bookId: widget.book.id,
      positionRatio: ratio,
      contentOffset: contentOffset,
      pageIndex: 0,
      totalPages: 0,
      updatedAt: DateTime.now(),
      scrollOffsetPx: offsetPx,
      scrollMaxExtentPx: maxExtentPx,
    );
    await _sessionController.saveProgress(progress);
  }

  void _scheduleProgressSave() {
    _progressSaver.schedule(_persistProgressNow);
  }

  Future<void> _jumpToContentOffset(int offset) async {
    if (_content.isEmpty) return;
    final clampedOffset = offset.clamp(0, _content.length);
    final ratio = (clampedOffset / _content.length).clamp(0.0, 1.0);

    _restoredContentOffset = clampedOffset;
    _restoredRatio = ratio;
    _lastKnownContentOffset = clampedOffset;

    if (_isDoubleActive) {
      final spreadPages = _spreadPages;
      if (spreadPages == null || spreadPages.length == 0) {
        _pendingAnchorOffset = clampedOffset;
        return;
      }
      final mapped = _mapSpreadIndexByOffset(spreadPages, clampedOffset);
      if (!mounted) return;
      setState(() {
        _spreadIndex = mapped;
      });
      _restoredScrollApplied = true;
      _lastKnownContentOffset = clampedOffset;
      _scheduleProgressSave();
      return;
    }

    final singlePages = _singlePages;
    if (singlePages == null || singlePages.length == 0) {
      _pendingAnchorOffset = clampedOffset;
      _restoredScrollApplied = false;
      return;
    }

    if (!_scrollController.hasClients || _singlePageExtent <= 0) {
      _restoredScrollApplied = false;
      _deferRestoreScrollIfNeeded();
      return;
    }

    final mapped = _findPageIndexByOffset(singlePages, clampedOffset);
    _singleIndex = mapped;
    _restoredScrollApplied = true;
    final target = (_singlePageExtent * mapped).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
  }

  void _goSpread({required bool forward}) {
    final pages = _spreadPages;
    if (pages == null || pages.length == 0) {
      return;
    }
    final next = _spreadIndex + (forward ? 2 : -2);
    final clamped = _layout.clampPageIndex(
      next,
      totalPages: pages.length,
      step: 2,
    );
    if (clamped == _spreadIndex) {
      return;
    }
    setState(() {
      _spreadIndex = clamped;
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
    return _layout.clampPageIndex(raw, totalPages: pages.length, step: 2);
  }

  double _singlePageExtentForViewport(double viewportHeight) {
    return (viewportHeight - (readerVerticalPadding * 2)).clamp(120.0, 8000.0);
  }

  Future<void> _goSinglePage({required bool forward}) async {
    final pages = _singlePages;
    if (pages == null || pages.length == 0) return;
    if (!_scrollController.hasClients || _singlePageExtent <= 0) return;
    final next = (_singleIndex + (forward ? 1 : -1)).clamp(0, pages.length - 1);
    if (next == _singleIndex) return;
    _singleIndex = next;
    final target = (_singlePageExtent * next).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
    _scheduleProgressSave();
  }

  void _ensureSinglePagination({
    required Size viewport,
    required MediaQueryData mediaQueryData,
    required TextStyle style,
  }) {
    if (_content.isEmpty) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;

    _singlePageExtent = _singlePageExtentForViewport(viewport.height);
    final signature = _layout.paginationSignature(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    if (signature == _singleSignature && _singlePages != null) {
      if (_pendingAnchorOffset != null) {
        final mapped = _findPageIndexByOffset(
          _singlePages!,
          _pendingAnchorOffset!,
        );
        _singleIndex = mapped;
      }
      return;
    }
    if (signature == _activeSingleSignature) {
      return;
    }

    _activeSingleSignature = signature;
    final token = ++_singleToken;
    final requestedAnchor =
        (_pendingAnchorOffset ?? _resolveStableAnchorOffset()).clamp(
          0,
          _content.length,
        );
    setState(() {
      _isSinglePaginating = true;
    });

    final textArea = _layout.textAreaForPagination(
      viewport,
      mediaQueryData: mediaQueryData,
    );

    unawaited(() async {
      try {
        final result = await _sessionController.paginate(
          bookId: widget.book.id,
          content: _content,
          signature: signature,
          textArea: textArea,
          textStyle: style,
          spreadStep: 1,
          restoredProgress: null,
          previousTotalPages: 0,
          previousRatio: 0,
          previewPageCount: 50,
          onPreviewReady: (previewPages) {
            if (!mounted || token != _singleToken) return;
            final liveAnchor = (_pendingAnchorOffset ?? requestedAnchor).clamp(
              0,
              _content.length,
            );
            final mapped = _findPageIndexByOffset(previewPages, liveAnchor);
            _singleIndex = mapped;
            setState(() {
              _singlePages = previewPages;
              _singleSignature = signature;
            });
            _lastKnownContentOffset = previewPages.ranges[mapped].start.clamp(
              0,
              _content.length,
            );
          },
        );
        if (!mounted || token != _singleToken) return;
        final liveAnchor = (_pendingAnchorOffset ?? requestedAnchor).clamp(
          0,
          _content.length,
        );
        final mapped = _findPageIndexByOffset(result.pages, liveAnchor);
        _singleIndex = mapped;
        setState(() {
          _singlePages = result.pages;
          _singleSignature = signature;
          _isSinglePaginating = false;
        });
        _lastKnownContentOffset = result.pages.ranges[mapped].start.clamp(
          0,
          _content.length,
        );
      } catch (_) {
        if (!mounted || token != _singleToken) return;
        setState(() {
          _isSinglePaginating = false;
        });
      } finally {
        if (_activeSingleSignature == signature) {
          _activeSingleSignature = null;
        }
      }
    }());
  }

  void _ensureSpreadPagination({
    required Size viewport,
    required MediaQueryData mediaQueryData,
    required TextStyle style,
  }) {
    if (_content.isEmpty) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;

    final signature = _layout.paginationSignature(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    if (signature == _spreadSignature && _spreadPages != null) {
      if (_pendingAnchorOffset != null) {
        final mapped = _mapSpreadIndexByOffset(
          _spreadPages!,
          _pendingAnchorOffset!,
        );
        _pendingAnchorOffset = null;
        setState(() {
          _spreadIndex = mapped;
        });
      }
      return;
    }
    if (signature == _activeSpreadSignature) {
      return;
    }

    _activeSpreadSignature = signature;
    final token = ++_spreadToken;
    final requestedAnchor =
        (_pendingAnchorOffset ?? _resolveStableAnchorOffset()).clamp(
          0,
          _content.length,
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
          bookId: widget.book.id,
          content: _content,
          signature: signature,
          textArea: textArea,
          textStyle: style,
          spreadStep: 2,
          restoredProgress: null,
          previousTotalPages: 0,
          previousRatio: 0,
          previewPageCount: 30,
          onPreviewReady: (previewPages) {
            if (!mounted || token != _spreadToken) return;
            final liveAnchor = (_pendingAnchorOffset ?? requestedAnchor).clamp(
              0,
              _content.length,
            );
            final mapped = _mapSpreadIndexByOffset(previewPages, liveAnchor);
            setState(() {
              _spreadPages = previewPages;
              _spreadIndex = mapped;
              _spreadSignature = signature;
            });
            _lastKnownContentOffset = previewPages.ranges[mapped].start.clamp(
              0,
              _content.length,
            );
          },
        );
        if (!mounted || token != _spreadToken) return;
        final liveAnchor = (_pendingAnchorOffset ?? requestedAnchor).clamp(
          0,
          _content.length,
        );
        final mapped = _mapSpreadIndexByOffset(result.pages, liveAnchor);
        setState(() {
          _spreadPages = result.pages;
          _spreadIndex = mapped;
          _spreadSignature = signature;
          _isSpreadPaginating = false;
        });
        _lastKnownContentOffset = result.pages.ranges[mapped].start.clamp(
          0,
          _content.length,
        );
        _pendingAnchorOffset = null;
      } catch (_) {
        if (!mounted || token != _spreadToken) return;
        setState(() {
          _isSpreadPaginating = false;
        });
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
    final result = await showReaderSettingsSheet(
      context: context,
      initialSettings: _settings,
      normalFontSize: readerFontSizeNormal,
      largeFontSize: readerFontSizeLarge,
    );

    if (result == null) {
      return;
    }

    final changed = result.toRaw() != _settings.toRaw();
    if (!changed) {
      return;
    }

    setState(() {
      _settings = result;
    });

    await _sessionController.saveSettings(result);
    await _applyWakelock();
  }

  void _handleTapNavigation({
    required TapUpDetails details,
    required BoxConstraints constraints,
    required bool doubleMode,
  }) {
    final action = _layout.resolveTapAction(
      dx: details.localPosition.dx,
      width: constraints.maxWidth,
    );
    switch (action) {
      case ReaderTapAction.previous:
        if (doubleMode) {
          _goSpread(forward: false);
        } else {
          unawaited(_goSinglePage(forward: false));
        }
        break;
      case ReaderTapAction.next:
        if (doubleMode) {
          _goSpread(forward: true);
        } else {
          unawaited(_goSinglePage(forward: true));
        }
        break;
      case ReaderTapAction.toggleControls:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;

    return Scaffold(
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
        final doubleMode = _layout.isDoublePageMode(
          viewport,
          mediaQueryData: mediaQueryData,
        );
        final wasDoubleMode = _isDoubleActive;
        final modeSwitchAnchor = (doubleMode != wasDoubleMode)
            ? _resolveStableAnchorOffset()
            : null;
        _isDoubleActive = doubleMode;
        _singlePageExtent = _singlePageExtentForViewport(constraints.maxHeight);
        if (modeSwitchAnchor != null) {
          _pendingAnchorOffset = modeSwitchAnchor.clamp(0, _content.length);
        }

        if (doubleMode) {
          if (!_restoredScrollApplied &&
              (_restoredContentOffset != null || _restoredRatio != null)) {
            _pendingAnchorOffset = _restoredContentOffset?.clamp(
              0,
              _content.length,
            );
            _pendingAnchorOffset ??=
                ((_restoredRatio!.clamp(0.0, 1.0)) * _content.length).round();
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _isDoubleActive) return;
            _ensureSinglePagination(
              viewport: viewport,
              mediaQueryData: mediaQueryData,
              style: style,
            );
          });
          _deferRestoreScrollIfNeeded();
          if (_pendingAnchorOffset != null) {
            final target = _pendingAnchorOffset!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _isDoubleActive) return;
              if (_singlePages == null || _singlePages!.length == 0) return;
              _pendingAnchorOffset = null;
              unawaited(_jumpToContentOffset(target));
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
            singlePages: _singlePages,
            singlePageExtent: _singlePageExtent,
            isSinglePaginating: _isSinglePaginating,
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
