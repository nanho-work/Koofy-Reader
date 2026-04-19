part of 'reader_page.dart';

extension _ReaderPageDiagnostics on _ReaderPageState {
  static const bool _lightweightTraceMode = true;
  static const Set<String> _lightweightTraceEvents = <String>{
    'single_scroll_state',
    'spread_scroll_state',
    'viewport_state',
    'double_viewport_settling',
    'double_viewport_stable',
  };

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
    final mode = _isDoubleActive ? 'double' : 'single';
    final suffix = details == null ? '' : ' details=$details';
    if (_lightweightTraceMode && _lightweightTraceEvents.contains(event)) {
      debugPrint(
        '[ReaderPos][$event] '
        'mode=$mode '
        'offset=$safeOffset '
        'pending=$_pendingAnchorOffset restored=$_restoredContentOffset '
        'last=$_lastKnownContentOffset '
        'jumping=$_isSpreadJumping modeEpoch=$_modeEpoch$suffix',
      );
      return;
    }
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
          _requestRebuild();
        }
      }
    });
    _tracePosition(
      'double_viewport_settling',
      offset: _restoredContentOffset ?? _lastKnownContentOffset,
      details: 'signature=$signature',
    );
  }

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

  void _ensureDoubleRestorePersistenceHold({required String reason}) {
    _doubleRestorePersistenceRelease ??= _holdProgressPersistence(reason);
  }

  void _releaseDoubleRestorePersistenceHold({required String reason}) {
    final release = _doubleRestorePersistenceRelease;
    if (release == null) {
      return;
    }
    _doubleRestorePersistenceRelease = null;
    release();
    _tracePosition(
      'progress_persist_double_restore_released',
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
    if (_isDoubleActive) {
      return _normalizeToDoubleRestoreOffset(raw).clamp(0, _content.length);
    }
    return _normalizeToSingleRestoreOffset(raw).clamp(0, _content.length);
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
}
