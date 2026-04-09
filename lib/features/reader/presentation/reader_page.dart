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
import 'package:koofy_reader/features/reader/presentation/controllers/reader_layout_controller.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_search_controller.dart';
import 'package:koofy_reader/features/reader/presentation/controllers/reader_session_controller.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_bottom_panel.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_dialogs.dart';
import 'package:koofy_reader/features/reader/presentation/widgets/reader_page_pane.dart';
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

  String _content = '';
  String? _errorText;
  bool _isBootstrapping = true;
  bool _isPaginating = false;

  ReaderSettings _settings = ReaderSettings.defaults();
  ReadingProgress? _restoredProgress;
  PaginatedText? _pages;

  int _pageIndex = 0;
  Set<int> _bookmarks = <int>{};
  List<String> _searchHistory = <String>[];
  String _activeQuery = '';
  List<int> _queryPages = <int>[];
  int _queryCursor = -1;
  bool _controlsExpanded = true;

  Timer? _saveDebounce;
  Size? _lastViewport;
  String? _activePaginationSignature;
  String? _lastPaginationSignature;
  int _paginationToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _saveDebounce?.cancel();
    unawaited(_persistProgressNow());
    unawaited(WakelockPlus.disable());
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
      _restoredProgress = data.progress;
      _searchHistory = data.searchHistory;
      _content = data.content;

      await _applyWakelock();

      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
      });
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

  int get _totalPages => _pages?.length ?? 0;

  int get _displayPage {
    if (_totalPages == 0) return 0;
    return (_pageIndex + 1).clamp(1, _totalPages);
  }

  double get _progressRatio {
    if (_totalPages <= 1) return 0;
    return (_pageIndex / (_totalPages - 1)).clamp(0.0, 1.0);
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

  void _ensurePagination(Size viewport, {bool force = false}) {
    if (_content.isEmpty) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;

    _lastViewport = viewport;
    final signature = _layout.paginationSignature(viewport);
    if (!force && signature == _lastPaginationSignature && _pages != null) {
      return;
    }
    if (signature == _activePaginationSignature) {
      return;
    }

    _activePaginationSignature = signature;
    unawaited(_paginate(viewport: viewport, signature: signature));
  }

  Future<void> _paginate({
    required Size viewport,
    required String signature,
  }) async {
    final token = ++_paginationToken;
    final previousTotalPages = _totalPages;
    final previousRatio = _progressRatio;

    if (mounted) {
      setState(() {
        _isPaginating = true;
      });
    }

    try {
      final area = _layout.textAreaForPagination(viewport);
      final style = _readerTextStyle(_palette);

      if (!mounted || token != _paginationToken) {
        return;
      }

      final spreadStep = _layout.spreadStepFor(viewport);
      final result = await _sessionController.paginate(
        bookId: widget.book.id,
        content: _content,
        signature: signature,
        textArea: area,
        textStyle: style,
        spreadStep: spreadStep,
        restoredProgress: _restoredProgress,
        previousTotalPages: previousTotalPages,
        previousRatio: previousRatio,
      );
      if (!mounted || token != _paginationToken) {
        return;
      }

      setState(() {
        _pages = result.pages;
        _pageIndex = result.pageIndex;
        if (result.restoredProgressConsumed) {
          _restoredProgress = null;
        }
        _isPaginating = false;
        _lastPaginationSignature = signature;
      });

      _scheduleProgressSave();
      _refreshQueryResultsForCurrentPagination();
    } catch (error) {
      if (!mounted || token != _paginationToken) {
        return;
      }
      setState(() {
        _errorText = '페이지 계산 실패: $error';
        _isPaginating = false;
      });
    } finally {
      if (_activePaginationSignature == signature) {
        _activePaginationSignature = null;
      }
    }
  }

  Future<void> _persistProgressNow() async {
    if (_pages == null || _totalPages == 0) {
      return;
    }
    final progress = ReadingProgress(
      bookId: widget.book.id,
      positionRatio: _progressRatio,
      pageIndex: _pageIndex,
      totalPages: _totalPages,
      updatedAt: DateTime.now(),
    );
    await _sessionController.saveProgress(progress);
  }

  void _scheduleProgressSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_persistProgressNow());
    });
  }

  void _goToPage(int target) {
    final pages = _pages;
    final viewport = _lastViewport;
    if (pages == null || viewport == null) return;

    final step = _layout.spreadStepFor(viewport);
    final clamped = _layout.clampPageIndex(
      target,
      totalPages: pages.length,
      step: step,
    );
    if (clamped == _pageIndex) {
      return;
    }

    setState(() {
      _pageIndex = clamped;
    });
    _scheduleProgressSave();
  }

  void _goNext() {
    final viewport = _lastViewport;
    if (viewport == null) return;
    _goToPage(_pageIndex + _layout.spreadStepFor(viewport));
  }

  void _goPrev() {
    final viewport = _lastViewport;
    if (viewport == null) return;
    _goToPage(_pageIndex - _layout.spreadStepFor(viewport));
  }

  void _handleTapNavigation(TapUpDetails details, Size viewport) {
    final action = _layout.resolveTapAction(
      dx: details.localPosition.dx,
      width: viewport.width,
    );
    switch (action) {
      case ReaderTapAction.previous:
        _goPrev();
        break;
      case ReaderTapAction.next:
        _goNext();
        break;
      case ReaderTapAction.toggleControls:
        setState(() {
          _controlsExpanded = !_controlsExpanded;
        });
        break;
    }
  }

  void _toggleCurrentBookmark() {
    if (_totalPages == 0) return;

    setState(() {
      if (_bookmarks.contains(_pageIndex)) {
        _bookmarks.remove(_pageIndex);
      } else {
        _bookmarks.add(_pageIndex);
      }
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
      _goToPage(target);
    }
  }

  Future<void> _openJumpDialog() async {
    if (_totalPages == 0) {
      return;
    }

    final result = await showReaderPageJumpDialog(
      context: context,
      totalPages: _totalPages,
      currentPage: _displayPage,
    );

    if (result == null) {
      return;
    }
    final clamped = result.clamp(1, _totalPages) - 1;
    _goToPage(clamped);
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
        _queryPages = <int>[];
        _queryCursor = -1;
      });
      return;
    }

    final searchController = _buildSearchController();
    if (searchController == null) {
      return;
    }

    final pages = searchController.findQueryPages(trimmed);
    final history = ReaderSearchController.normalizeHistory([
      trimmed,
      ..._searchHistory,
    ]);

    setState(() {
      _activeQuery = trimmed;
      _queryPages = pages;
      _queryCursor = pages.isEmpty ? -1 : 0;
      _searchHistory = history;
    });

    unawaited(_sessionController.saveSearchHistory(history));

    if (pages.isNotEmpty) {
      _goToPage(pages.first);
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('검색 결과가 없습니다.')));
    }
  }

  void _refreshQueryResultsForCurrentPagination() {
    if (_activeQuery.isEmpty || _pages == null) {
      return;
    }
    final searchController = _buildSearchController();
    if (searchController == null) {
      return;
    }
    final pages = searchController.findQueryPages(_activeQuery);
    if (!mounted) {
      return;
    }
    setState(() {
      _queryPages = pages;
      if (pages.isEmpty) {
        _queryCursor = -1;
      } else if (_queryCursor < 0 || _queryCursor >= pages.length) {
        _queryCursor = 0;
      }
    });
  }

  void _moveQueryCursor(int delta) {
    if (_queryPages.isEmpty) {
      return;
    }
    final normalized = ReaderSearchController.moveCursor(
      current: _queryCursor,
      delta: delta,
      length: _queryPages.length,
    );

    setState(() {
      _queryCursor = normalized;
    });
    _goToPage(_queryPages[normalized]);
  }

  ReaderSearchController? _buildSearchController() {
    final pages = _pages;
    if (pages == null) {
      return null;
    }
    return ReaderSearchController(source: _content, ranges: pages.ranges);
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
      _lastPaginationSignature = null;
    });

    await _sessionController.saveSettings(result);
    await _applyWakelock();

    final viewport = _lastViewport;
    if (viewport != null) {
      _ensurePagination(viewport, force: true);
    }
  }

  void _setFontPreset(bool large) {
    final target = large ? readerFontSizeLarge : readerFontSizeNormal;
    if ((_settings.fontSize - target).abs() < 0.01) {
      return;
    }

    final next = _settings.copyWith(fontSize: target);
    setState(() {
      _settings = next;
      _lastPaginationSignature = null;
    });
    unawaited(_sessionController.saveSettings(next));

    final viewport = _lastViewport;
    if (viewport != null) {
      _ensurePagination(viewport, force: true);
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
          if (_queryPages.isNotEmpty)
            IconButton(
              onPressed: () => _moveQueryCursor(-1),
              icon: const Icon(Icons.keyboard_arrow_left),
              tooltip: '이전 검색',
            ),
          if (_queryPages.isNotEmpty)
            IconButton(
              onPressed: () => _moveQueryCursor(1),
              icon: const Icon(Icons.keyboard_arrow_right),
              tooltip: '다음 검색',
            ),
          IconButton(
            onPressed: _openSearchDialog,
            icon: const Icon(Icons.search),
            tooltip: '검색',
          ),
          IconButton(
            onPressed: _openBookmarksSheet,
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: '북마크 목록',
          ),
          IconButton(
            onPressed: _openReaderSettingsSheet,
            icon: const Icon(Icons.tune),
            tooltip: '읽기 설정',
          ),
        ],
      ),
      body: _buildBody(palette),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pages != null && _pages!.length > 0)
              _buildBottomControlPanel(palette),
            const AdFooterWidget(),
          ],
        ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _ensurePagination(viewport);

        if (_pages == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final style = _readerTextStyle(palette);
        final doubleMode = _layout.isDoublePageMode(viewport);
        final rightPage = _pageIndex + 1;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapNavigation(details, viewport),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: readerVerticalPadding,
                ),
                child: doubleMode
                    ? Row(
                        children: [
                          Expanded(
                            child: ReaderPagePane(
                              text: _pages![_pageIndex],
                              style: style,
                              backgroundColor: palette.background,
                              horizontalPadding: _settings.horizontalPadding,
                            ),
                          ),
                          Container(
                            width: readerDoublePageGap,
                            color: palette.background,
                            alignment: Alignment.center,
                            child: Container(width: 1, color: palette.divider),
                          ),
                          Expanded(
                            child: rightPage < _totalPages
                                ? ReaderPagePane(
                                    text: _pages![rightPage],
                                    style: style,
                                    backgroundColor: palette.background,
                                    horizontalPadding:
                                        _settings.horizontalPadding,
                                  )
                                : ReaderPagePane(
                                    text: '',
                                    style: style,
                                    backgroundColor: palette.background,
                                    horizontalPadding:
                                        _settings.horizontalPadding,
                                  ),
                          ),
                        ],
                      )
                    : ReaderPagePane(
                        text: _pages![_pageIndex],
                        style: style,
                        backgroundColor: palette.background,
                        horizontalPadding: _settings.horizontalPadding,
                      ),
              ),
              if (_isPaginating)
                Positioned(
                  top: 10,
                  right: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.panel,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text('페이지 계산 중...'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomControlPanel(ReaderPalette palette) {
    return ReaderBottomPanel(
      panelColor: palette.panel,
      displayPage: _displayPage,
      totalPages: _totalPages,
      pageIndex: _pageIndex,
      progressRatio: _progressRatio,
      controlsExpanded: _controlsExpanded,
      isCurrentBookmarked: _bookmarks.contains(_pageIndex),
      currentFontSize: _settings.fontSize,
      normalFontSize: readerFontSizeNormal,
      largeFontSize: readerFontSizeLarge,
      activeQuery: _activeQuery,
      queryCursor: _queryCursor,
      queryTotal: _queryPages.length,
      onPageChanged: _goToPage,
      onPrevPage: _goPrev,
      onNextPage: _goNext,
      onToggleBookmark: _toggleCurrentBookmark,
      onJump: () => unawaited(_openJumpDialog()),
      onSearch: () => unawaited(_openSearchDialog()),
      onSetNormalFont: () => _setFontPreset(false),
      onSetLargeFont: () => _setFontPreset(true),
    );
  }
}
