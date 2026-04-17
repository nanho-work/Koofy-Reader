import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/reader/application/controllers/reader_location_controller.dart';
import 'package:koofy_reader/features/reader/application/controllers/reader_navigation_controller.dart';
import 'package:koofy_reader/features/reader/application/controllers/reader_presentation_controller.dart';
import 'package:koofy_reader/features/reader/application/state/reader_location_state.dart';
import 'package:koofy_reader/features/reader/core/models/reader_search_result.dart';
import 'package:koofy_reader/features/reader/core/models/reader_text_document.dart';
import 'package:koofy_reader/features/reader/core/services/reader_content_indexer.dart';
import 'package:koofy_reader/features/reader/core/services/reader_mode_transition_service.dart';
import 'package:koofy_reader/features/reader/core/services/reader_position_service.dart';
import 'package:koofy_reader/features/reader/core/services/reader_progress_coordinator.dart';
import 'package:koofy_reader/features/reader/core/services/reader_projection_service.dart';
import 'package:koofy_reader/features/reader/core/services/reader_spread_pagination_service.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';
import 'package:koofy_reader/features/reader/domain/reader_font_keys.dart';
import 'package:koofy_reader/features/reader/data/reader_settings_repository.dart';
import 'package:koofy_reader/features/reader/data/text_pagination_engine.dart';
import 'package:koofy_reader/features/reader/data/reader_font_registry.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';
import 'package:koofy_reader/features/reader/domain/reader_structure_index.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';
import 'package:koofy_reader/features/reader/engine/reader_engine.dart';
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
  late final ReaderEngine _readerEngine;
  late final ReaderSessionController _sessionController;
  final ReaderLocationController _locationController =
      const ReaderLocationController();
  final ReaderNavigationController _navigationController =
      const ReaderNavigationController();
  final ReaderPresentationController _presentationController =
      const ReaderPresentationController();
  final ReaderProgressSaver _progressSaver = ReaderProgressSaver();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _spreadScrollController = ScrollController();

  String _content = '';
  ReaderTextDocument? _document;
  String? _errorText;
  bool _isBootstrapping = true;

  ReaderSettings _settings = ReaderSettings.defaults();
  int? _restoredContentOffset;
  int? _restoredDoublePageStartOffset;
  double? _restoredSingleScrollRatio;
  ReaderProgressCoordinatorState _coordinatorState =
      const ReaderProgressCoordinatorState();
  int _lastKnownContentOffset = 0;
  List<ReaderParagraphRange> _paragraphRanges = const <ReaderParagraphRange>[];
  List<ReaderChapterRange> _chapterRanges = const <ReaderChapterRange>[];
  Set<int> _bookmarks = <int>{};
  List<String> _searchHistory = <String>[];

  String _activeQuery = '';
  List<ReaderSearchResult> _queryResults = <ReaderSearchResult>[];
  int _queryCursor = -1;

  String? _singleLayoutSignature;
  TextPainter? _singleTextPainter;
  double _singleViewportHeight = 0;
  PaginatedText? _spreadPages;
  int _spreadIndex = 0;
  int _spreadWindowStartOffset = 0;
  int _spreadWindowEndOffset = 0;
  int? _pendingSpreadForceStartOffset;
  String? _spreadSignature;
  String? _activeSpreadSignature;
  int _spreadToken = 0;
  bool _isSpreadPaginating = false;
  bool _isDoubleActive = false;
  double _spreadViewportExtent = 0;
  int _modeEpoch = 0;
  bool _hasInitializedMode = false;
  bool _spreadPaginationFrameQueued = false;
  bool _isSearchDialogOpen = false;
  String? _pendingSearchQuery;
  int? _pendingSearchJumpOffset;
  Timer? _modeTransitionDebounce;
  bool _modeTransitionApplyQueued = false;
  bool _modeTransitionRequestQueued = false;
  bool _isPersistingPop = false;
  int _progressPersistenceHoldCount = 0;
  VoidCallback? _modeTransitionPersistenceRelease;
  VoidCallback? _searchJumpPersistenceRelease;
  int _singleRestoreVerificationToken = 0;
  String? _lastViewportLogSignature;
  String? _lastDoubleViewportSettleSignature;
  int? _lastSingleScrollLogBucket;
  int? _lastSpreadScrollLogRow;
  bool _isSpreadJumping = false;
  int? _pinnedDoubleContentOffset;
  bool _isDoubleViewportSettling = false;
  Timer? _doubleViewportSettleTimer;
  final ReaderModeTransitionService _modeTransitionService =
      const ReaderModeTransitionService();
  final ReaderProgressCoordinator _progressCoordinator =
      const ReaderProgressCoordinator();
  final ReaderProjectionService _projectionService =
      const ReaderProjectionService();
  late final ReaderSpreadPaginationService _spreadPaginationService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScrollChanged);
    _spreadScrollController.addListener(_onSpreadScrollChanged);
    _readerEngine = const ReaderEngine();
    _spreadPaginationService = ReaderSpreadPaginationService(
      engine: TextPaginationEngine(),
    );
    _sessionController = ReaderSessionController(
      readerRepository: ref.read(readerRepositoryProvider),
      settingsRepository: ref.read(readerSettingsRepositoryProvider),
      bookRepository: ref.read(bookRepositoryProvider),
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScrollChanged);
    _spreadScrollController.removeListener(_onSpreadScrollChanged);
    _progressSaver.cancel();
    _modeTransitionDebounce?.cancel();
    _doubleViewportSettleTimer?.cancel();
    _modeTransitionPersistenceRelease = null;
    _searchJumpPersistenceRelease = null;
    _progressPersistenceHoldCount = 0;
    _modeTransitionApplyQueued = false;
    unawaited(_persistProgressNow(force: true));
    unawaited(WakelockPlus.disable());
    _scrollController.dispose();
    _spreadScrollController.dispose();
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
      _restoredContentOffset = _resolveStoredOffset(data.progress);
      _restoredDoublePageStartOffset = _readerEngine
          .resolveDoublePageStartOffset(
            document: _document,
            progress: data.progress,
          );
      _restoredSingleScrollRatio =
          (data.progress?.scrollOffsetPx != null &&
              data.progress?.scrollMaxExtentPx != null &&
              (data.progress!.scrollMaxExtentPx! > 0))
          ? (data.progress!.scrollOffsetPx! / data.progress!.scrollMaxExtentPx!)
                .clamp(0.0, 1.0)
          : null;
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
      _scheduleDeferredFontPreparation();
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

  bool get _restoredScrollApplied => _coordinatorState.restoredScrollApplied;
  set _restoredScrollApplied(bool value) {
    _coordinatorState = _coordinatorState.copyWith(
      restoredScrollApplied: value,
    );
  }

  int? get _pendingAnchorOffset => _coordinatorState.pendingAnchorOffset;
  set _pendingAnchorOffset(int? value) {
    _coordinatorState = value == null
        ? _coordinatorState.copyWith(clearPendingAnchorOffset: true)
        : _coordinatorState.copyWith(pendingAnchorOffset: value);
  }

  bool get _isModeTransitioning => _coordinatorState.isModeTransitioning;
  set _isModeTransitioning(bool value) {
    _coordinatorState = _coordinatorState.copyWith(isModeTransitioning: value);
  }

  bool? get _modeTransitionTarget => _coordinatorState.modeTransitionTarget;
  set _modeTransitionTarget(bool? value) {
    _coordinatorState = value == null
        ? _coordinatorState.copyWith(clearModeTransitionTarget: true)
        : _coordinatorState.copyWith(modeTransitionTarget: value);
  }

  int? get _pendingModeAnchorOffset =>
      _coordinatorState.pendingModeAnchorOffset;
  set _pendingModeAnchorOffset(int? value) {
    _coordinatorState = value == null
        ? _coordinatorState.copyWith(clearPendingModeAnchorOffset: true)
        : _coordinatorState.copyWith(pendingModeAnchorOffset: value);
  }

  bool get _preserveRawPendingSingleAnchor =>
      _coordinatorState.preserveRawPendingSingleAnchor;

  int _normalizeToSingleRestoreOffset(int offset) {
    return ReaderPositionService.normalizeRestoreOffset(
      content: _content,
      offset: offset,
      doubleMode: false,
      singlePainter: _singleTextPainter,
    );
  }

  int _normalizeToDoubleRestoreOffset(int offset) {
    return ReaderPositionService.normalizeRestoreOffset(
      content: _content,
      offset: offset,
      doubleMode: true,
    );
  }

  Future<bool> _normalizeAndLoadFont() async {
    if (ReaderFontKeys.isBuiltin(_settings.fontKey)) {
      return false;
    }
    final registry = ref.read(readerFontRegistryProvider);
    final fonts = await registry.loadAvailableFonts();
    var shouldInvalidate = false;
    final exists = fonts.any((font) => font.key == _settings.fontKey);
    if (!exists) {
      shouldInvalidate = true;
      _settings = ReaderSettings.defaults().copyWith(
        backgroundMode: _settings.backgroundMode,
        pageLayoutMode: _settings.pageLayoutMode,
        fontSize: _settings.fontSize,
        lineHeight: _settings.lineHeight,
        horizontalPadding: _settings.horizontalPadding,
        keepScreenOn: _settings.keepScreenOn,
      );
    }
    final loadedNewFont = await registry.ensureLoadedForKey(_settings.fontKey);
    return shouldInvalidate || loadedNewFont;
  }

  void _scheduleDeferredFontPreparation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(() async {
        final shouldInvalidate = await _normalizeAndLoadFont();
        if (!mounted || !shouldInvalidate) {
          return;
        }
        setState(() {
          _invalidateLayoutCaches();
          _restoredScrollApplied = false;
        });
      }());
    });
  }

  void _invalidateLayoutCaches() {
    _singleLayoutSignature = null;
    _singleTextPainter = null;
    _singleViewportHeight = 0;
    _spreadSignature = null;
    _activeSpreadSignature = null;
    _spreadToken++;
    _isSpreadPaginating = false;
  }

  void _indexContent(ReaderStructureIndex? structureIndex) {
    final document = _readerEngine.buildDocument(
      content: _content,
      structureIndex: structureIndex,
    );
    _document = document;
    _paragraphRanges = document.paragraphRanges;
    _chapterRanges = document.chapterRanges;
  }

  int? _resolveStoredOffset(ReadingProgress? progress) {
    return _readerEngine.resolveStoredOffset(
      document: _document,
      progress: progress,
      onResolved: (source, resolvedOffset) {
        if (source == 'anchor') {
          _tracePosition(
            'resolve_stored_offset_anchor',
            offset: resolvedOffset,
            anchor: progress?.anchor,
          );
          return;
        }
        _tracePosition(
          'resolve_stored_offset_fallback',
          offset: resolvedOffset,
          details: 'source=$source',
        );
      },
    );
  }

  ReadingAnchor _buildAnchorForOffset(int offset) {
    final document = _document;
    if (document != null) {
      return _readerEngine.buildAnchorForOffset(
        document: document,
        offset: offset,
      );
    }
    return ReaderContentIndexer.buildAnchorForOffset(
      offset: offset,
      contentLength: _content.length,
      paragraphRanges: _paragraphRanges,
      chapterRanges: _chapterRanges,
    );
  }

  int? _offsetFromAnchor(ReadingAnchor? anchor) {
    final document = _document;
    if (document != null) {
      return _readerEngine.offsetFromAnchor(document: document, anchor: anchor);
    }
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
    final currentSpreadIndex = _spreadPages == null || _spreadPages!.length == 0
        ? _spreadIndex
        : _currentSpreadStartIndex();
    final spreadStart =
        (_spreadPages != null && _spreadPages!.ranges.isNotEmpty)
        ? _spreadPages!
              .ranges[currentSpreadIndex.clamp(0, _spreadPages!.length - 1)]
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
      'last=$_lastKnownContentOffset spreadIndex=$currentSpreadIndex spreadStart=$spreadStart '
      'jumping=$_isSpreadJumping modeEpoch=$_modeEpoch$suffix',
    );
  }

  void _traceViewportState({
    required Size viewport,
    required MediaQueryData mediaQueryData,
    required bool requestedDoubleMode,
  }) {
    if (!kDebugMode || _content.isEmpty) {
      return;
    }
    final signature = [
      viewport.width.toStringAsFixed(1),
      viewport.height.toStringAsFixed(1),
      requestedDoubleMode ? 'double' : 'single',
      _isDoubleActive ? 'double' : 'single',
      mediaQueryData.padding.top.toStringAsFixed(1),
      mediaQueryData.padding.bottom.toStringAsFixed(1),
      mediaQueryData.viewInsets.bottom.toStringAsFixed(1),
    ].join('|');
    if (signature == _lastViewportLogSignature) {
      return;
    }
    _lastViewportLogSignature = signature;
    _tracePosition(
      'viewport_state',
      offset: _resolveStableAnchorOffset(),
      details:
          'viewport=${viewport.width.toStringAsFixed(1)}x${viewport.height.toStringAsFixed(1)} requested=${requestedDoubleMode ? 'double' : 'single'} active=${_isDoubleActive ? 'double' : 'single'} paddingTop=${mediaQueryData.padding.top.toStringAsFixed(1)} paddingBottom=${mediaQueryData.padding.bottom.toStringAsFixed(1)} insetBottom=${mediaQueryData.viewInsets.bottom.toStringAsFixed(1)}',
    );
  }

  void _trackDoubleViewportStability({
    required Size viewport,
    required MediaQueryData mediaQueryData,
    required bool requestedDoubleMode,
  }) {
    double bucket(double value, double step) =>
        ((value / step).round() * step).toDouble();
    if (!requestedDoubleMode && !_isDoubleActive) {
      _doubleViewportSettleTimer?.cancel();
      _lastDoubleViewportSettleSignature = null;
      _isDoubleViewportSettling = false;
      return;
    }

    final signature = [
      bucket(viewport.width, 12).toStringAsFixed(0),
      bucket(viewport.height, 12).toStringAsFixed(0),
      bucket(mediaQueryData.padding.bottom, 4).toStringAsFixed(0),
      bucket(mediaQueryData.viewInsets.bottom, 4).toStringAsFixed(0),
      (requestedDoubleMode || _isDoubleActive) ? 'double' : 'single',
    ].join('|');
    if (signature == _lastDoubleViewportSettleSignature) {
      return;
    }
    _lastDoubleViewportSettleSignature = signature;
    _isDoubleViewportSettling = true;
    _doubleViewportSettleTimer?.cancel();
    _doubleViewportSettleTimer = Timer(const Duration(milliseconds: 180), () {
      _isDoubleViewportSettling = false;
      if (!mounted) {
        return;
      }
      _tracePosition(
        'double_viewport_stable',
        offset: _restoredContentOffset ?? _lastKnownContentOffset,
        details: 'signature=$signature',
      );
      _flushPendingSearchQueryIfPossible();
      _flushPendingSearchJumpIfPossible();
      _flushProgressPersistenceHolds(reason: 'double_viewport_stable');
      if (_isDoubleActive) {
        _scheduleProgressSave();
        final shouldRebuild =
            _pendingAnchorOffset != null ||
            _spreadPages == null ||
            _pendingSearchQuery != null ||
            _pendingSearchJumpOffset != null;
        if (shouldRebuild) {
          setState(() {});
        }
      }
    });
    _tracePosition(
      'double_viewport_settling',
      offset: _restoredContentOffset ?? _lastKnownContentOffset,
      details: 'signature=$signature',
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

  bool get _hasPendingPositionMutation {
    return _progressCoordinator.hasPendingMutation(
          state: _coordinatorState,
          isSpreadPaginating: _isSpreadPaginating,
          isSpreadJumping: _isSpreadJumping,
        ) ||
        _isDoubleViewportSettling;
  }

  int _stableProgressOffset() {
    return _progressCoordinator.stableProgressOffset(
      state: _coordinatorState,
      restoredContentOffset: _restoredContentOffset,
      lastKnownContentOffset: _lastKnownContentOffset,
      contentLength: _content.length,
    );
  }

  ReaderLocationState _currentLocationState() {
    return _locationController.build(
      content: _content,
      isDoubleActive: _isDoubleActive,
      singlePainter: _singleTextPainter,
      hasSingleScrollClients: _scrollController.hasClients,
      singleScrollOffset: _scrollController.hasClients
          ? _scrollController.offset
          : 0,
      singleMaxScrollExtent: _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0,
      singleViewportHeight: _singleViewportHeight,
      spreadPages: _spreadPages,
      spreadIndex: _spreadIndex,
      isSpreadJumping: _isSpreadJumping,
      hasSpreadClients: _spreadScrollController.hasClients,
      spreadViewportExtent: _spreadViewportExtent,
      spreadScrollOffset: _spreadScrollController.hasClients
          ? _spreadScrollController.offset
          : 0,
      lastKnownContentOffset: _lastKnownContentOffset,
      pendingAnchorOffset: _pendingAnchorOffset,
      restoredContentOffset: _restoredContentOffset,
      restoredDoublePageStartOffset: _restoredDoublePageStartOffset,
      pinnedDoubleContentOffset: _pinnedDoubleContentOffset,
    );
  }

  int _currentSingleFocusOffset() {
    return _currentLocationState().singleFocusOffset;
  }

  int _preferredDoubleModeAnchorOffset() {
    final transitionAnchor = !_isDoubleActive
        ? _currentSingleFocusOffset()
        : _resolveStableAnchorOffset();
    return _progressCoordinator.preferredDoubleAnchorOffset(
      state: _coordinatorState,
      restoredDoublePageStartOffset: _isDoubleActive
          ? _currentDoublePageStartOffset()
          : null,
      restoredContentOffset: _restoredContentOffset,
      stableAnchorOffset: transitionAnchor,
      lastKnownContentOffset: _lastKnownContentOffset,
      contentLength: _content.length,
    );
  }

  int? _currentDoublePageStartOffset() {
    return _currentLocationState().doublePageStartOffset;
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
    _tracePosition(
      'single_layout_built',
      offset: _resolveStableAnchorOffset(),
      details:
          'maxWidth=${maxWidth.toStringAsFixed(1)} viewportHeight=${viewport.height.toStringAsFixed(1)} painterHeight=${painter.height.toStringAsFixed(1)}',
    );
  }

  int _currentSingleContentOffset() {
    return _currentLocationState().singleContentOffset;
  }

  double _singleScrollOffsetForContentOffset(
    int contentOffset, {
    bool preserveRawOffset = false,
  }) {
    return _projectionService.singleScrollOffsetForContentOffset(
      content: _content,
      painter: _singleTextPainter,
      contentOffset: contentOffset,
      preserveRawOffset: preserveRawOffset,
      hasScrollClients: _scrollController.hasClients,
      maxScrollExtent: _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0,
      singleViewportHeight: _singleViewportHeight,
    );
  }

  double _singleScrollOffsetForRawContentOffset(int contentOffset) {
    return _singleScrollOffsetForContentOffset(
      contentOffset,
      preserveRawOffset: true,
    );
  }

  bool get _isProgressPersistenceHeld => _progressPersistenceHoldCount > 0;

  VoidCallback _holdProgressPersistence(String reason) {
    var released = false;
    _progressPersistenceHoldCount++;
    _tracePosition(
      'progress_persist_hold',
      details: 'reason=$reason depth=$_progressPersistenceHoldCount',
    );
    return () {
      if (released) {
        return;
      }
      released = true;
      if (_progressPersistenceHoldCount > 0) {
        _progressPersistenceHoldCount--;
      }
      _tracePosition(
        'progress_persist_release',
        details: 'reason=$reason depth=$_progressPersistenceHoldCount',
      );
      if (_progressPersistenceHoldCount == 0) {
        _scheduleProgressSave();
      }
    };
  }

  void _releaseModeTransitionPersistenceHold({required String reason}) {
    final release = _modeTransitionPersistenceRelease;
    if (release == null) {
      return;
    }
    _modeTransitionPersistenceRelease = null;
    release();
    _tracePosition('progress_persist_mode_released', details: 'reason=$reason');
  }

  void _releaseSearchJumpPersistenceHold({required String reason}) {
    final release = _searchJumpPersistenceRelease;
    if (release == null) {
      return;
    }
    _searchJumpPersistenceRelease = null;
    release();
    _tracePosition(
      'progress_persist_search_released',
      details: 'reason=$reason',
    );
  }

  void _flushProgressPersistenceHolds({required String reason}) {
    if (_modeTransitionPersistenceRelease != null &&
        !_isModeTransitioning &&
        !_isDoubleViewportSettling &&
        !_isSpreadPaginating &&
        !_isSpreadJumping &&
        _pendingAnchorOffset == null) {
      _releaseModeTransitionPersistenceHold(reason: reason);
    }
    if (_searchJumpPersistenceRelease != null &&
        !_isSearchDialogOpen &&
        _pendingSearchQuery == null &&
        _pendingSearchJumpOffset == null &&
        !_isDoubleViewportSettling &&
        !_isSpreadPaginating &&
        !_isSpreadJumping) {
      _releaseSearchJumpPersistenceHold(reason: reason);
    }
  }

  int _normalizeSearchJumpOffset(int offset) {
    if (_content.isEmpty) {
      return 0;
    }
    final raw = offset.clamp(0, _content.length);
    return ReaderPositionService.normalizeToLineStartOffset(
      content: _content,
      offset: raw,
    ).clamp(0, _content.length);
  }

  void _queueSearchJump(int offset) {
    _searchJumpPersistenceRelease ??= _holdProgressPersistence('search_jump');
    _pendingSearchJumpOffset = _normalizeSearchJumpOffset(offset);
    _tracePosition(
      'search_jump_queued',
      offset: _pendingSearchJumpOffset,
      details: 'raw=$offset',
    );
    _flushPendingSearchJumpIfPossible();
  }

  void _flushPendingSearchQueryIfPossible() {
    final pending = _pendingSearchQuery;
    if (pending == null) {
      return;
    }
    if (_isSearchDialogOpen ||
        _isModeTransitioning ||
        _isDoubleViewportSettling ||
        _isSpreadPaginating ||
        _isSpreadJumping) {
      return;
    }
    _pendingSearchQuery = null;
    _applySearchQueryNow(pending);
  }

  void _flushPendingSearchJumpIfPossible() {
    final pending = _pendingSearchJumpOffset;
    if (pending == null) {
      return;
    }
    if (_isSearchDialogOpen ||
        _isModeTransitioning ||
        _isDoubleViewportSettling ||
        _isSpreadPaginating ||
        _isSpreadJumping) {
      return;
    }
    _pendingSearchJumpOffset = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        _jumpToContentOffset(
          pending,
          animate: false,
          preserveRawSingleOffset: false,
        ),
      );
    });
  }

  void _scheduleSingleRestoreVerification(
    int targetOffset, {
    required String reason,
    int attempt = 0,
  }) {
    final verificationToken = ++_singleRestoreVerificationToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _isDoubleActive ||
          verificationToken != _singleRestoreVerificationToken) {
        return;
      }
      if (!_scrollController.hasClients || _singleTextPainter == null) {
        return;
      }
      final expected = _normalizeToSingleRestoreOffset(
        targetOffset,
      ).clamp(0, _content.length);
      final actual = _currentSingleContentOffset().clamp(0, _content.length);
      final delta = (actual - expected).abs();
      _tracePosition(
        'restore_single_verify',
        offset: actual,
        details:
            'expected=$expected delta=$delta attempt=$attempt reason=$reason',
      );
      if (delta <= 1 || attempt >= 2) {
        return;
      }
      final correctedTarget = _singleScrollOffsetForContentOffset(expected);
      final currentPixels = _scrollController.offset;
      if ((currentPixels - correctedTarget).abs() <= 0.5) {
        return;
      }
      _scrollController.jumpTo(correctedTarget);
      _lastKnownContentOffset = _currentContentOffset().clamp(
        0,
        _content.length,
      );
      _scheduleSingleRestoreVerification(
        expected,
        reason: reason,
        attempt: attempt + 1,
      );
    });
  }

  int _currentContentOffset() {
    return _currentLocationState().contentOffset;
  }

  int _resolveStableAnchorOffset() {
    return _currentLocationState().stableAnchorOffset;
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
    if (_scrollController.hasClients) {
      final bucket = (_scrollController.offset / 48).floor();
      if (bucket != _lastSingleScrollLogBucket) {
        _lastSingleScrollLogBucket = bucket;
        _tracePosition(
          'single_scroll_state',
          offset: _lastKnownContentOffset,
          details:
              'pixels=${_scrollController.offset.toStringAsFixed(1)} max=${_scrollController.position.maxScrollExtent.toStringAsFixed(1)} bucket=$bucket',
        );
      }
    }
    _scheduleProgressSave();
  }

  int _currentSpreadStartIndex() {
    return _currentLocationState().spreadStartIndex;
  }

  void _onSpreadScrollChanged() {
    if (_isBootstrapping || _content.isEmpty || _isModeTransitioning) return;
    if (!_isDoubleActive) return;
    if (_isDoubleViewportSettling) return;
    final pages = _spreadPages;
    if (pages == null || pages.length == 0) return;
    if (_isSpreadJumping) {
      return;
    }
    final logicalSpreadIndex = _currentSpreadStartIndex();
    _spreadIndex = logicalSpreadIndex;
    final pinned = _pinnedDoubleContentOffset;
    if (pinned != null) {
      final safeIndex = logicalSpreadIndex.clamp(0, pages.length - 1);
      final left = pages.ranges[safeIndex];
      final right = pages.ranges[(safeIndex + 1).clamp(0, pages.length - 1)];
      if (pinned < left.start || pinned >= right.end) {
        _pinnedDoubleContentOffset = null;
      }
    }
    _lastKnownContentOffset = _currentContentOffset().clamp(0, _content.length);
    if (_spreadScrollController.hasClients && _spreadViewportExtent > 0) {
      final row = (_spreadScrollController.offset / _spreadViewportExtent)
          .round();
      if (row != _lastSpreadScrollLogRow) {
        _lastSpreadScrollLogRow = row;
        _tracePosition(
          'spread_scroll_state',
          offset: _lastKnownContentOffset,
          details:
              'pixels=${_spreadScrollController.offset.toStringAsFixed(1)} row=$row viewportExtent=${_spreadViewportExtent.toStringAsFixed(1)} max=${_spreadScrollController.position.maxScrollExtent.toStringAsFixed(1)}',
        );
      }
    }
    _scheduleProgressSave();
  }

  void _deferRestoreScrollIfNeeded() {
    _coordinatorState = _progressCoordinator.resolveRestoredOffset(
      state: _coordinatorState,
      restoredContentOffset: _restoredContentOffset,
      isDoubleActive: _isDoubleActive,
    );

    if (_restoredScrollApplied) {
      return;
    }
    final restoredOffsetRaw = _restoredContentOffset;
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
          if (attempts == 1 || attempts == maxAttempts) {
            _tracePosition(
              'restore_single_wait_scroll',
              offset: restoredOffsetRaw,
              details: 'attempt=$attempts max=$maxAttempts',
            );
          }
          if (attempts < maxAttempts) {
            attemptRestore();
            return;
          }
          _restoredScrollApplied = true;
          return;
        }
        if (_singleTextPainter == null) {
          attempts += 1;
          if (attempts == 1 || attempts == maxAttempts) {
            _tracePosition(
              'restore_single_wait_layout',
              offset: restoredOffsetRaw,
              details: 'attempt=$attempts max=$maxAttempts',
            );
          }
          if (attempts < maxAttempts) {
            attemptRestore();
            return;
          }
          _restoredScrollApplied = true;
          return;
        }
        final restoredOffset = restoredOffsetRaw.clamp(0, _content.length);
        final target = _restoredSingleScrollRatio != null
            ? (_restoredSingleScrollRatio! *
                      _scrollController.position.maxScrollExtent)
                  .clamp(0.0, _scrollController.position.maxScrollExtent)
            : _singleScrollOffsetForRawContentOffset(restoredOffset);
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
        _scheduleSingleRestoreVerification(
          restoredOffset,
          reason: 'deferred_restore',
        );
        _restoredScrollApplied = true;
      });
    }

    attemptRestore();
  }

  Future<void> _persistProgressNow({bool force = false}) async {
    if (_content.isEmpty ||
        ((_hasPendingPositionMutation || _isProgressPersistenceHeld) &&
            !force)) {
      return;
    }
    final rawOffset =
        ((_hasPendingPositionMutation || _isProgressPersistenceHeld)
                ? _stableProgressOffset()
                : _currentContentOffset())
            .clamp(0, _content.length);
    final contentOffset = rawOffset;
    final isSingleActive = !_isDoubleActive;
    final offsetPx = isSingleActive && _scrollController.hasClients
        ? _scrollController.offset
        : null;
    final maxExtentPx = isSingleActive && _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : null;
    final ratio = isSingleActive && offsetPx != null && maxExtentPx != null
        ? (maxExtentPx <= 0 ? 0.0 : (offsetPx / maxExtentPx).clamp(0.0, 1.0))
        : (_content.isEmpty
              ? 0.0
              : (rawOffset / _content.length).clamp(0.0, 1.0));
    final doublePageStartOffset = isSingleActive
        ? null
        : _currentDoublePageStartOffset();
    _tracePosition(
      'save_progress',
      offset: contentOffset,
      anchor: _buildAnchorForOffset(contentOffset),
      details:
          'force=$force ratio=${ratio.toStringAsFixed(4)} doublePageStart=${doublePageStartOffset ?? 'null'} hold=$_progressPersistenceHoldCount',
    );

    final progress = _readerEngine.buildProgress(
      bookId: widget.book.id,
      document: _document,
      contentOffset: contentOffset,
      updatedAt: DateTime.now(),
      doublePageStartOffset: doublePageStartOffset,
      scrollOffsetPx: offsetPx,
      scrollMaxExtentPx: maxExtentPx,
    );
    await _sessionController.saveProgress(progress);
  }

  void _scheduleProgressSave() {
    if (_hasPendingPositionMutation || _isProgressPersistenceHeld) {
      return;
    }
    _progressSaver.schedule(_persistProgressNow);
  }

  Future<void> _jumpToContentOffset(
    int offset, {
    bool animate = true,
    bool preserveRawSingleOffset = false,
  }) async {
    if (_content.isEmpty) return;
    final clampedOffset = offset.clamp(0, _content.length);
    final targetOffset = _isDoubleActive
        ? _normalizeToDoubleRestoreOffset(clampedOffset)
        : clampedOffset;
    _tracePosition(
      'jump_request',
      offset: targetOffset,
      details:
          'mode=${_isDoubleActive ? 'double' : 'single'} preserveRawSingle=$preserveRawSingleOffset raw=$clampedOffset',
    );

    _restoredContentOffset = targetOffset;
    _restoredSingleScrollRatio = null;
    _lastKnownContentOffset = targetOffset;

    if (_isDoubleActive) {
      _pinnedDoubleContentOffset = targetOffset;
      final pages = _spreadPages;
      if (pages != null &&
          pages.length > 0 &&
          _spreadSignature != null &&
          _containsOffset(pages, targetOffset)) {
        final mapped = _mapSpreadIndexByOffset(pages, targetOffset);
        await _jumpSpreadToIndex(mapped, animate: animate);
        _tracePosition(
          'jump_applied_double_reuse',
          offset: _lastKnownContentOffset,
          details: 'mapped=$mapped animate=$animate',
        );
        _flushProgressPersistenceHolds(reason: 'jump_applied_double_reuse');
        return;
      }
      _requestSpreadWindowRepagination(
        targetOffset,
        forceStartOffset: targetOffset,
      );
      _tracePosition('jump_request_double_repaginate', offset: targetOffset);
      return;
    }

    if (_singleTextPainter == null || !_scrollController.hasClients) {
      _coordinatorState = _progressCoordinator
          .deferSingleJump(
            state: _coordinatorState,
            targetOffset: targetOffset,
            contentLength: _content.length,
          )
          .state;
      _tracePosition(
        'jump_request_single_deferred',
        offset: targetOffset,
        details: 'layoutNotReady=true',
      );
      return;
    }
    _coordinatorState = _progressCoordinator
        .applySingleJump(state: _coordinatorState)
        .state;
    final target = preserveRawSingleOffset
        ? _singleScrollOffsetForRawContentOffset(targetOffset)
        : _singleScrollOffsetForContentOffset(targetOffset);
    if (animate) {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollController.jumpTo(target);
    }
    final actualOffset = _currentContentOffset().clamp(0, _content.length);
    _lastKnownContentOffset = actualOffset;
    _tracePosition(
      'jump_applied_single',
      offset: _lastKnownContentOffset,
      details:
          'targetPx=${target.toStringAsFixed(1)} actual=$actualOffset preserveRawSingle=$preserveRawSingleOffset',
    );
    _flushProgressPersistenceHolds(reason: 'jump_applied_single');
    _scheduleSingleRestoreVerification(
      targetOffset,
      reason: animate ? 'jump_animate' : 'jump_immediate',
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
    if (_isSpreadPaginating || _isSpreadJumping) {
      return;
    }
    _pinnedDoubleContentOffset = null;
    final pages = _spreadPages;
    if (pages == null || pages.length == 0) {
      return;
    }
    final current = _spreadIndex.clamp(0, pages.length - 1);
    final rowCount = (pages.length / 2).ceil();
    final currentRow = (current / 2).floor();
    final rawTargetRow = currentRow + (forward ? 1 : -1);
    if (rawTargetRow < 0 || rawTargetRow >= rowCount) {
      final hasMore = forward
          ? _spreadWindowEndOffset < _content.length
          : _spreadWindowStartOffset > 0;
      if (!hasMore) {
        return;
      }
      final anchorOffset = forward
          ? pages.ranges.last.end.clamp(0, _content.length)
          : (pages.ranges.first.start - 1).clamp(0, _content.length);
      _requestSpreadWindowRepagination(
        anchorOffset,
        forceStartOffset: forward ? anchorOffset : null,
      );
      return;
    }
    final targetRow = rawTargetRow.clamp(0, rowCount - 1);
    if (targetRow == currentRow) {
      return;
    }
    final targetIndex = _clampSpreadStartIndex(targetRow * 2, pages.length);
    unawaited(_jumpSpreadToIndex(targetIndex, animate: true));
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  int _mapSpreadIndexByOffset(PaginatedText pages, int offset) {
    return _projectionService.mapSpreadIndexByOffset(
      pages,
      offset.clamp(0, pages.source.length),
    );
  }

  bool _containsOffset(PaginatedText pages, int offset) {
    return _projectionService.containsOffset(
      pages: pages,
      offset: offset,
      contentLength: _content.length,
    );
  }

  void _requestSpreadWindowRepagination(
    int anchorOffset, {
    int? forceStartOffset,
  }) {
    _pendingAnchorOffset = _normalizeToDoubleRestoreOffset(
      anchorOffset.clamp(0, _content.length),
    );
    _pinnedDoubleContentOffset = _pendingAnchorOffset;
    _pendingSpreadForceStartOffset = forceStartOffset?.clamp(
      0,
      _content.length,
    );
    _spreadSignature = null;
    _activeSpreadSignature = null;
    _spreadToken++;
    _tracePosition(
      'spread_repaginate_requested',
      offset: _pendingAnchorOffset,
      details:
          'spreadToken=$_spreadToken forceStart=${_pendingSpreadForceStartOffset ?? 'null'}',
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _jumpSpreadToIndex(
    int spreadStartIndex, {
    bool animate = false,
  }) async {
    final pages = _spreadPages;
    if (pages == null || pages.length == 0) {
      return;
    }
    final clamped = _clampSpreadStartIndex(spreadStartIndex, pages.length);
    _spreadIndex = clamped;
    _coordinatorState = _progressCoordinator
        .applySpreadJump(state: _coordinatorState)
        .state;
    if (!_spreadScrollController.hasClients || _spreadViewportExtent <= 0) {
      _coordinatorState = _progressCoordinator
          .deferSpreadJump(state: _coordinatorState, spreadJumpIndex: clamped)
          .state;
      _tracePosition(
        'spread_jump_deferred',
        offset: pages.ranges[clamped].start.clamp(0, _content.length),
        details:
            'index=$clamped animate=$animate viewportExtent=${_spreadViewportExtent.toStringAsFixed(1)}',
      );
      return;
    }
    final row = (clamped / 2).floor();
    final target = (row * _spreadViewportExtent).clamp(
      0.0,
      _spreadScrollController.position.maxScrollExtent,
    );
    _isSpreadJumping = true;
    try {
      if (animate) {
        await _spreadScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else {
        _spreadScrollController.jumpTo(target);
      }
      await _waitForNextFrame();
    } finally {
      _isSpreadJumping = false;
    }
    _spreadIndex = clamped;
    _restoredDoublePageStartOffset = pages.ranges[clamped].start.clamp(
      0,
      _content.length,
    );
    _lastKnownContentOffset =
        (_isDoubleViewportSettling && _restoredContentOffset != null)
        ? _restoredContentOffset!.clamp(0, _content.length)
        : _currentContentOffset().clamp(0, _content.length);
    _tracePosition(
      'spread_jump_applied',
      offset: _lastKnownContentOffset,
      details:
          'index=$clamped row=$row targetPx=${target.toStringAsFixed(1)} animate=$animate',
    );
    _flushProgressPersistenceHolds(reason: 'spread_jump_applied');
    _scheduleProgressSave();
  }

  void _scheduleModeTransition(ReaderModeTransitionRequest request) {
    _modeTransitionPersistenceRelease ??= _holdProgressPersistence(
      'mode_transition',
    );
    final transitionStart = _progressCoordinator.beginModeTransition(
      state: _coordinatorState,
      targetDoubleMode: request.targetDoubleMode,
      anchorOffset: request.anchorOffset,
      preserveRawPendingSingleAnchor: request.preserveRawSingleAnchor,
      contentLength: _content.length,
    );
    _coordinatorState = transitionStart.state;
    final clampedAnchor = transitionStart.anchorOffset;
    final previewNormalized = request.targetDoubleMode
        ? _normalizeToDoubleRestoreOffset(clampedAnchor)
        : _normalizeToSingleRestoreOffset(clampedAnchor);
    _tracePosition(
      'mode_transition_schedule',
      offset: clampedAnchor,
      details:
          'target=${request.targetDoubleMode ? 'double' : 'single'} previewNormalized=$previewNormalized delayMs=${request.delayMs}',
    );

    _modeEpoch++;
    // Invalidate any in-flight spread pagination so stale callbacks
    // cannot overwrite the position during mode transitions.
    _spreadToken++;
    _activeSpreadSignature = null;
    _spreadSignature = null;
    if (request.targetDoubleMode) {
      // Prevent stale spread pages from flashing while transitioning.
      _spreadPages = null;
      _spreadIndex = 0;
      _isSpreadPaginating = false;
    }

    void applyTransitionNow() {
      if (!mounted || _modeTransitionApplyQueued) return;
      _modeTransitionApplyQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _modeTransitionApplyQueued = false;
        if (!mounted) return;
        final transitionApply = _progressCoordinator.resolveModeTransitionApply(
          state: _coordinatorState,
          fallbackTargetDoubleMode: request.targetDoubleMode,
          fallbackAnchorOffset: clampedAnchor,
          contentLength: _content.length,
        );
        _coordinatorState = transitionApply.state;
        final applyMode = transitionApply.targetDoubleMode;
        final applyAnchor = transitionApply.anchorOffset;
        setState(() {
          _isDoubleActive = applyMode;
          if (applyMode) {
            _pinnedDoubleContentOffset = applyAnchor;
            _singleLayoutSignature = null;
            _singleTextPainter = null;
            _singleViewportHeight = 0;
            _spreadPages = null;
            _spreadIndex = 0;
            _spreadSignature = null;
            _activeSpreadSignature = null;
          } else {
            _pinnedDoubleContentOffset = null;
            _isSpreadPaginating = false;
            _spreadPages = null;
            _spreadIndex = 0;
            _spreadSignature = null;
            _activeSpreadSignature = null;
          }
        });
        _tracePosition(
          'mode_transition_applied',
          offset: applyAnchor,
          details:
              'applied=${applyMode ? 'double' : 'single'} preserveRawSingle=$_preserveRawPendingSingleAnchor',
        );
      });
    }

    _modeTransitionDebounce?.cancel();
    if (request.delayMs <= 0) {
      applyTransitionNow();
      return;
    }
    _modeTransitionDebounce = Timer(
      Duration(milliseconds: request.delayMs),
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
    final document = _document;
    if (document == null) return;
    if (_content.isEmpty) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;
    if (_isDoubleViewportSettling) return;
    // Do not paginate spread pages while transitioning to single mode.
    if (_isModeTransitioning && _modeTransitionTarget == false) {
      return;
    }

    final layoutSignature = _layout.paginationSignature(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    final textArea = _layout.textAreaForPagination(
      viewport,
      mediaQueryData: mediaQueryData,
    );
    final requestedAnchor = _normalizeToDoubleRestoreOffset(
      (_pendingAnchorOffset ??
              (_isDoubleViewportSettling && _restoredContentOffset != null
                  ? _restoredContentOffset
                  : _pinnedDoubleContentOffset) ??
              _resolveStableAnchorOffset())
          .clamp(0, _content.length),
    );
    if (layoutSignature == _spreadSignature &&
        _spreadPages != null &&
        _containsOffset(_spreadPages!, requestedAnchor)) {
      if (_pendingAnchorOffset != null) {
        final pending = _pendingAnchorOffset!.clamp(0, _content.length);
        final mapped = _mapSpreadIndexByOffset(_spreadPages!, pending);
        _coordinatorState = _progressCoordinator.clearConsumedPendingAnchor(
          _coordinatorState,
        );
        unawaited(() async {
          await _jumpSpreadToIndex(mapped);
          _flushProgressPersistenceHolds(reason: 'spread_paginate_reuse');
        }());
      }
      return;
    }
    final requestSignature = '$layoutSignature|$requestedAnchor';
    if (requestSignature == _activeSpreadSignature) {
      return;
    }

    _activeSpreadSignature = requestSignature;
    final token = ++_spreadToken;
    final modeEpochAtRequest = _modeEpoch;
    _tracePosition(
      'spread_paginate_start',
      offset: requestedAnchor,
      details: 'signature=$requestSignature token=$token',
    );
    setState(() {
      _isSpreadPaginating = true;
    });

    unawaited(() async {
      try {
        final result = await _spreadPaginationService.paginate(
          document: document,
          layoutSignature: layoutSignature,
          textArea: textArea,
          style: style,
          anchorOffset: requestedAnchor,
          forceStartOffset: _pendingSpreadForceStartOffset,
        );
        if (!mounted ||
            token != _spreadToken ||
            _modeEpoch != modeEpochAtRequest ||
            !_isDoubleActive) {
          return;
        }
        setState(() {
          _spreadPages = result.pages;
          _spreadIndex = result.mappedIndex;
          _spreadSignature = layoutSignature;
          _isSpreadPaginating = false;
          _spreadWindowStartOffset = result.windowStartOffset;
          _spreadWindowEndOffset = result.windowEndOffset;
          _pendingSpreadForceStartOffset = null;
        });
        await _jumpSpreadToIndex(result.mappedIndex);
        _pendingAnchorOffset = null;
        _tracePosition(
          result.fromCache
              ? 'spread_paginate_cache_hit'
              : 'spread_paginate_done',
          offset: result.requestedAnchor,
          details:
              'mapped=${result.mappedIndex} signature=${result.signature} window=${result.windowStartOffset}:${result.windowEndOffset} fallback=${result.usedFallbackWindow} durationMs=${result.durationMs ?? 0}',
        );
        _flushProgressPersistenceHolds(reason: 'spread_paginate_done');
      } catch (_) {
        if (!mounted || token != _spreadToken) return;
        setState(() {
          _isSpreadPaginating = false;
          _pendingSpreadForceStartOffset = null;
        });
        _tracePosition(
          'spread_paginate_error',
          offset: requestedAnchor,
          details: 'token=$token',
        );
        _flushProgressPersistenceHolds(reason: 'spread_paginate_error');
      } finally {
        if (_activeSpreadSignature == requestSignature) {
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
    setState(() {
      _isSearchDialogOpen = true;
      _pendingSearchJumpOffset = null;
    });
    final query = await showReaderSearchDialog(
      context: context,
      initialQuery: _activeQuery,
      history: _searchHistory,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isSearchDialogOpen = false;
    });

    if (query == null) {
      return;
    }
    _pendingSearchQuery = query;
    _flushPendingSearchQueryIfPossible();
  }

  void _applySearchQueryNow(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _releaseSearchJumpPersistenceHold(reason: 'search_cleared');
      setState(() {
        _activeQuery = '';
        _queryResults = <ReaderSearchResult>[];
        _queryCursor = -1;
      });
      return;
    }

    final document = _document;
    final results = document == null
        ? const <ReaderSearchResult>[]
        : _readerEngine.search(document: document, query: trimmed);
    final history = _readerEngine.normalizeSearchHistory([
      trimmed,
      ..._searchHistory,
    ]);
    _tracePosition(
      'search_query_applied',
      offset: _lastKnownContentOffset,
      details: 'query=$trimmed matches=${results.length}',
    );

    setState(() {
      _activeQuery = trimmed;
      _queryResults = results;
      _queryCursor = results.isEmpty ? -1 : 0;
      _searchHistory = history;
    });

    unawaited(_sessionController.saveSearchHistory(history));

    if (results.isNotEmpty) {
      _queueSearchJumpResult(results.first);
      return;
    }

    _releaseSearchJumpPersistenceHold(reason: 'search_no_results');

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('검색 결과가 없습니다.')));
    }
  }

  void _moveQueryCursor(int delta) {
    if (_queryResults.isEmpty) {
      return;
    }
    final normalized = ReaderSearchController.moveCursor(
      current: _queryCursor,
      delta: delta,
      length: _queryResults.length,
    );

    setState(() {
      _queryCursor = normalized;
    });
    _queueSearchJumpResult(_queryResults[normalized]);
  }

  void _queueSearchJumpResult(ReaderSearchResult result) {
    _tracePosition(
      'search_result_selected',
      offset: result.locator.globalOffset,
      details:
          'query=${result.query} paragraph=${result.anchor.paragraphIndex}',
    );
    _queueSearchJump(result.locator.globalOffset);
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
      _restoredSingleScrollRatio = null;
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
    final command = _navigationController.resolveTapCommand(
      dx: details.localPosition.dx,
      width: constraints.maxWidth,
      doubleMode: doubleMode,
      isSpreadPaginating: _isSpreadPaginating,
      isSpreadJumping: _isSpreadJumping,
      isDoubleViewportSettling: _isDoubleViewportSettling,
    );
    switch (command) {
      case ReaderNavigationCommand.none:
        return;
      case ReaderNavigationCommand.singlePrevious:
        unawaited(_goSingleScrollByViewport(forward: false));
        break;
      case ReaderNavigationCommand.singleNext:
        unawaited(_goSingleScrollByViewport(forward: true));
        break;
      case ReaderNavigationCommand.doublePrevious:
        _goSpread(forward: false);
        break;
      case ReaderNavigationCommand.doubleNext:
        _goSpread(forward: true);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final mediaQueryData = MediaQuery.of(context);
    final scaffoldRequestedDoubleMode =
        (_isSearchDialogOpen || _pendingSearchQuery != null)
        ? _isDoubleActive
        : _layout.isDoublePageMode(
            mediaQueryData.size,
            mediaQueryData: mediaQueryData,
          );
    final presentationState = _presentationController.build(
      requestedDoubleMode: scaffoldRequestedDoubleMode,
      hasPendingPositionMutation: _hasPendingPositionMutation,
      hasQueryMatches: _queryResults.isNotEmpty,
    );

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
              hasQueryMatches: presentationState.hasQueryMatches,
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
        bottomNavigationBar: presentationState.shouldShowFooterAd
            ? const SafeArea(child: AdFooterWidget())
            : null,
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
        final computedDoubleMode = _layout.isDoublePageMode(
          viewport,
          mediaQueryData: mediaQueryData,
        );
        if (!_hasInitializedMode) {
          _hasInitializedMode = true;
          _isDoubleActive = computedDoubleMode;
          _tracePosition(
            'initial_mode_set',
            offset: _resolveStableAnchorOffset(),
            details: 'mode=${computedDoubleMode ? 'double' : 'single'}',
          );
        }
        final requestedDoubleMode =
            (_isSearchDialogOpen || _pendingSearchQuery != null)
            ? _isDoubleActive
            : computedDoubleMode;
        _trackDoubleViewportStability(
          viewport: viewport,
          mediaQueryData: mediaQueryData,
          requestedDoubleMode: requestedDoubleMode,
        );
        final modeTransitionRequest = _modeTransitionService.buildRequest(
          requestedDoubleMode: requestedDoubleMode,
          activeDoubleMode: _isDoubleActive,
          preferredDoubleAnchorOffset: _preferredDoubleModeAnchorOffset(),
          stableAnchorOffset: _resolveStableAnchorOffset(),
          pendingModeAnchorOffset: _pendingModeAnchorOffset,
          contentLength: _content.length,
        );
        final hasPendingRequestedTransition =
            modeTransitionRequest != null &&
            _modeTransitionService.hasPendingRequestedTransition(
              requestedDoubleMode: modeTransitionRequest.targetDoubleMode,
              modeTransitionTarget: _modeTransitionTarget,
              pendingModeAnchorOffset: _pendingModeAnchorOffset,
            );
        _traceViewportState(
          viewport: viewport,
          mediaQueryData: mediaQueryData,
          requestedDoubleMode: requestedDoubleMode,
        );
        _spreadViewportExtent = constraints.maxHeight.clamp(1.0, 10000.0);
        if (modeTransitionRequest != null) {
          if (!_modeTransitionRequestQueued && !hasPendingRequestedTransition) {
            _modeTransitionRequestQueued = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _modeTransitionRequestQueued = false;
              if (!mounted) {
                return;
              }
              if (requestedDoubleMode == _isDoubleActive &&
                  !_isModeTransitioning) {
                return;
              }
              _scheduleModeTransition(modeTransitionRequest);
            });
          }
        }
        final doubleMode = _isDoubleActive;
        final freezeOutgoingSingleLayout =
            !doubleMode && requestedDoubleMode != _isDoubleActive;
        if (!doubleMode && !freezeOutgoingSingleLayout) {
          _ensureSingleTextLayout(viewport: viewport, style: style);
        }

        if (doubleMode) {
          final doubleRestore = _progressCoordinator.beginDoubleRestore(
            state: _coordinatorState,
            preferredAnchorOffset: _preferredDoubleModeAnchorOffset(),
            hasRestoredContentOffset: _restoredContentOffset != null,
            contentLength: _content.length,
          );
          _coordinatorState = doubleRestore.state;
          if (doubleRestore.targetOffset != null) {
            _pinnedDoubleContentOffset = doubleRestore.targetOffset;
            _tracePosition(
              'double_restore_pending_set',
              offset: doubleRestore.targetOffset,
              details: 'fromProgress=true',
            );
          }
          if (!_spreadPaginationFrameQueued) {
            _spreadPaginationFrameQueued = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _spreadPaginationFrameQueued = false;
              if (!mounted || !_isDoubleActive) return;
              _ensureSpreadPagination(
                viewport: viewport,
                mediaQueryData: mediaQueryData,
                style: style,
              );
              final spreadJump = _progressCoordinator.consumePendingSpreadJump(
                state: _coordinatorState,
              );
              _coordinatorState = spreadJump.state;
              if (spreadJump.spreadJumpIndex != null) {
                unawaited(_jumpSpreadToIndex(spreadJump.spreadJumpIndex!));
              }
            });
          }
        } else {
          _deferRestoreScrollIfNeeded();
          _flushPendingSearchQueryIfPossible();
          _flushPendingSearchJumpIfPossible();
          if (_pendingAnchorOffset != null) {
            final pendingSingle = _progressCoordinator
                .consumePendingSingleAnchor(state: _coordinatorState);
            _coordinatorState = pendingSingle.state;
            final target = pendingSingle.targetOffset!;
            final preserveRawSingle = pendingSingle.preserveRawSingleAnchor;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _isDoubleActive) return;
              unawaited(() async {
                await _jumpToContentOffset(
                  target,
                  animate: false,
                  preserveRawSingleOffset: preserveRawSingle,
                );
                _flushProgressPersistenceHolds(
                  reason: 'single_anchor_consumed',
                );
              }());
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
            spreadScrollController: _spreadScrollController,
            spreadViewportExtent: _spreadViewportExtent,
            spreadPages: _spreadPages,
            isSpreadPaginating: _isSpreadPaginating,
          ),
        );
      },
    );
  }
}
