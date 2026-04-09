import 'dart:async';
import 'dart:math' as math;

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
import 'package:wakelock_plus/wakelock_plus.dart';

class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  static const double _doublePageGap = 18;
  static const double _verticalPadding = 16;
  static const double _fontSizeNormal = 19;
  static const double _fontSizeLarge = 23;

  late final ReaderRepository _readerRepository;
  late final ReaderSettingsRepository _settingsRepository;
  late final BookRepository _bookRepository;
  final TextPaginationEngine _paginationEngine = TextPaginationEngine();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _jumpController = TextEditingController();

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
    _readerRepository = ref.read(readerRepositoryProvider);
    _settingsRepository = ref.read(readerSettingsRepositoryProvider);
    _bookRepository = ref.read(bookRepositoryProvider);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _jumpController.dispose();
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
      final results = await Future.wait<dynamic>([
        _bookRepository.readBookContent(widget.book),
        _settingsRepository.load(),
        _readerRepository.loadBookmarks(widget.book.id),
        _readerRepository.loadProgress(widget.book.id),
        _readerRepository.loadSearchHistory(),
      ]);

      final rawContent = results[0] as String;
      final normalized = rawContent
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');

      _settings = results[1] as ReaderSettings;
      _bookmarks = (results[2] as Set<int>).where((page) => page >= 0).toSet();
      _restoredProgress = results[3] as ReadingProgress?;
      _searchHistory = results[4] as List<String>;
      _content = normalized;

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

  _ReaderPalette get _palette {
    switch (_settings.backgroundMode) {
      case ReaderBackgroundMode.black:
        return const _ReaderPalette(
          background: Color(0xFF111111),
          text: Color(0xFFF6F6F6),
          panel: Color(0xFF1A1A1A),
          divider: Color(0x33FFFFFF),
        );
      case ReaderBackgroundMode.beige:
        return const _ReaderPalette(
          background: Color(0xFFF3EBD9),
          text: Color(0xFF2D241A),
          panel: Color(0xFFE9DFC8),
          divider: Color(0x332D241A),
        );
      case ReaderBackgroundMode.gray:
        return const _ReaderPalette(
          background: Color(0xFFE2E2E2),
          text: Color(0xFF1F1F1F),
          panel: Color(0xFFD4D4D4),
          divider: Color(0x331F1F1F),
        );
    }
  }

  TextStyle _readerTextStyle(_ReaderPalette palette) {
    return TextStyle(
      color: palette.text,
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      fontFamily: _settings.fontFamily,
    );
  }

  bool _isDoublePageMode(Size viewport) {
    switch (_settings.pageLayoutMode) {
      case ReaderPageLayoutMode.single:
        return false;
      case ReaderPageLayoutMode.double:
        return true;
      case ReaderPageLayoutMode.auto:
        return viewport.width >= 820;
    }
  }

  int _spreadStepFor(Size viewport) => _isDoublePageMode(viewport) ? 2 : 1;

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

  Size _textAreaForPagination(Size viewport) {
    final double textHeight = math.max(
      120,
      viewport.height - (_verticalPadding * 2),
    );
    final bool isDouble = _isDoublePageMode(viewport);
    final double paneWidth = isDouble
        ? math.max(120, (viewport.width - _doublePageGap) / 2)
        : viewport.width;
    final double textWidth = math.max(
      80,
      paneWidth - (_settings.horizontalPadding * 2),
    );
    return Size(textWidth, textHeight);
  }

  String _paginationSignature(Size viewport) {
    final area = _textAreaForPagination(viewport);
    final mode = _isDoublePageMode(viewport) ? 'double' : 'single';
    return [
      mode,
      area.width.toStringAsFixed(1),
      area.height.toStringAsFixed(1),
      _settings.fontFamily,
      _settings.fontSize.toStringAsFixed(1),
      _settings.lineHeight.toStringAsFixed(2),
      _settings.horizontalPadding.toStringAsFixed(1),
    ].join('|');
  }

  void _ensurePagination(Size viewport, {bool force = false}) {
    if (_content.isEmpty) return;
    if (viewport.width <= 0 || viewport.height <= 0) return;

    _lastViewport = viewport;
    final signature = _paginationSignature(viewport);
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
      final area = _textAreaForPagination(viewport);
      final style = _readerTextStyle(_palette);

      final cachedOffsets = await _readerRepository.loadPaginationOffsets(
        bookId: widget.book.id,
        signature: signature,
        contentLength: _content.length,
      );

      PaginatedText paginated;
      if (cachedOffsets != null && cachedOffsets.isNotEmpty) {
        paginated = PaginatedText.fromBreakOffsets(
          source: _content,
          offsets: cachedOffsets,
        );
      } else {
        paginated = await _paginationEngine.paginateAsync(
          content: _content,
          maxWidth: area.width,
          maxHeight: area.height,
          style: style,
        );
        unawaited(
          _readerRepository.savePaginationOffsets(
            bookId: widget.book.id,
            signature: signature,
            contentLength: _content.length,
            offsets: paginated.toBreakOffsets(),
          ),
        );
      }

      if (!mounted || token != _paginationToken) {
        return;
      }

      final spreadStep = _spreadStepFor(viewport);
      final restored = _restoredProgress;
      int nextIndex = 0;

      if (restored != null) {
        if (restored.totalPages == paginated.length &&
            restored.pageIndex >= 0 &&
            restored.pageIndex < paginated.length) {
          nextIndex = restored.pageIndex;
        } else {
          nextIndex =
              (restored.positionRatio * math.max(0, paginated.length - 1))
                  .round();
        }
        _restoredProgress = null;
      } else if (previousTotalPages > 1) {
        nextIndex = (previousRatio * math.max(0, paginated.length - 1)).round();
      }

      nextIndex = _clampPageIndex(
        nextIndex,
        totalPages: paginated.length,
        step: spreadStep,
      );

      setState(() {
        _pages = paginated;
        _pageIndex = nextIndex;
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
    await _readerRepository.saveProgress(progress);
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

    final step = _spreadStepFor(viewport);
    final clamped = _clampPageIndex(
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
    _goToPage(_pageIndex + _spreadStepFor(viewport));
  }

  void _goPrev() {
    final viewport = _lastViewport;
    if (viewport == null) return;
    _goToPage(_pageIndex - _spreadStepFor(viewport));
  }

  void _handleTapNavigation(TapUpDetails details, Size viewport) {
    final width = viewport.width;
    if (width <= 0) return;
    final dx = details.localPosition.dx;
    final leftEdge = width * 0.28;
    final rightEdge = width * 0.72;

    if (dx <= leftEdge) {
      _goPrev();
      return;
    }
    if (dx >= rightEdge) {
      _goNext();
      return;
    }

    setState(() {
      _controlsExpanded = !_controlsExpanded;
    });
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
    unawaited(_readerRepository.saveBookmarks(widget.book.id, _bookmarks));
  }

  Future<void> _openBookmarksSheet() async {
    if (_bookmarks.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('등록된 북마크가 없습니다.')));
      return;
    }

    final sorted = _bookmarks.toList()..sort();
    final target = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView.separated(
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final page = sorted[index] + 1;
            return ListTile(
              title: Text('$page 페이지'),
              onTap: () => Navigator.pop(context, sorted[index]),
            );
          },
        );
      },
    );

    if (target != null) {
      _goToPage(target);
    }
  }

  Future<void> _openJumpDialog() async {
    if (_totalPages == 0) {
      return;
    }

    _jumpController.text = _displayPage.toString();
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('페이지 이동'),
          content: TextField(
            controller: _jumpController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: '1 ~ $_totalPages'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                final page = int.tryParse(_jumpController.text.trim());
                if (page == null) {
                  Navigator.pop(context);
                  return;
                }
                Navigator.pop(context, page);
              },
              child: const Text('이동'),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }
    final clamped = result.clamp(1, _totalPages) - 1;
    _goToPage(clamped);
  }

  Future<void> _openSearchDialog() async {
    _searchController.text = _activeQuery;
    final query = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('텍스트 검색'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(hintText: '검색어 입력'),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
              const SizedBox(height: 12),
              if (_searchHistory.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _searchHistory
                      .take(6)
                      .map(
                        (item) => ActionChip(
                          label: Text(item),
                          onPressed: () => Navigator.pop(context, item),
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('초기화'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _searchController.text),
              child: const Text('검색'),
            ),
          ],
        );
      },
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

    if (_pages == null) {
      return;
    }

    final pages = _findQueryPages(trimmed);
    final history = [trimmed, ..._searchHistory]
        .fold<List<String>>(<String>[], (acc, item) {
          final exists = acc.any(
            (saved) => saved.toLowerCase() == item.toLowerCase(),
          );
          if (!exists) {
            acc.add(item);
          }
          return acc;
        })
        .take(12)
        .toList();

    setState(() {
      _activeQuery = trimmed;
      _queryPages = pages;
      _queryCursor = pages.isEmpty ? -1 : 0;
      _searchHistory = history;
    });

    unawaited(_readerRepository.saveSearchHistory(history));

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
    final pages = _findQueryPages(_activeQuery);
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

  List<int> _findQueryPages(String query) {
    final pages = _pages;
    if (pages == null || query.isEmpty) {
      return const <int>[];
    }

    final lowerText = _content.toLowerCase();
    final needle = query.toLowerCase();
    final result = <int>[];
    int from = 0;

    while (from < lowerText.length) {
      final index = lowerText.indexOf(needle, from);
      if (index < 0) {
        break;
      }
      final page = _pageForOffset(index, pages.ranges);
      if (page >= 0 && (result.isEmpty || result.last != page)) {
        result.add(page);
      }
      from = index + needle.length;
    }

    return result;
  }

  int _pageForOffset(int offset, List<TextPageRange> ranges) {
    if (ranges.isEmpty) return -1;
    int low = 0;
    int high = ranges.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final range = ranges[mid];
      if (offset < range.start) {
        high = mid - 1;
      } else if (offset >= range.end) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    return ranges.length - 1;
  }

  void _moveQueryCursor(int delta) {
    if (_queryPages.isEmpty) {
      return;
    }
    final length = _queryPages.length;
    final current = _queryCursor < 0 ? 0 : _queryCursor;
    final next = (current + delta) % length;
    final normalized = next < 0 ? next + length : next;

    setState(() {
      _queryCursor = normalized;
    });
    _goToPage(_queryPages[normalized]);
  }

  Future<void> _openReaderSettingsSheet() async {
    final result = await showModalBottomSheet<ReaderSettings>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        var draft = _settings;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget sectionTitle(String text) {
              return Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              );
            }

            Widget choiceChip<T>(
              T value,
              T selected,
              String label,
              void Function(T) onChanged,
            ) {
              return ChoiceChip(
                label: Text(label),
                selected: value == selected,
                onSelected: (_) => setModalState(() => onChanged(value)),
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle('배경 모드'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        choiceChip(
                          ReaderBackgroundMode.black,
                          draft.backgroundMode,
                          '검정',
                          (value) =>
                              draft = draft.copyWith(backgroundMode: value),
                        ),
                        choiceChip(
                          ReaderBackgroundMode.beige,
                          draft.backgroundMode,
                          '베이지',
                          (value) =>
                              draft = draft.copyWith(backgroundMode: value),
                        ),
                        choiceChip(
                          ReaderBackgroundMode.gray,
                          draft.backgroundMode,
                          '회색',
                          (value) =>
                              draft = draft.copyWith(backgroundMode: value),
                        ),
                      ],
                    ),
                    sectionTitle('글자 크기'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        choiceChip(
                          _fontSizeNormal,
                          draft.fontSize,
                          '기본',
                          (value) => draft = draft.copyWith(fontSize: value),
                        ),
                        choiceChip(
                          _fontSizeLarge,
                          draft.fontSize,
                          '크게',
                          (value) => draft = draft.copyWith(fontSize: value),
                        ),
                      ],
                    ),
                    sectionTitle('폰트'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        choiceChip(
                          ReaderFontOption.sans,
                          draft.fontOption,
                          'Sans',
                          (value) => draft = draft.copyWith(fontOption: value),
                        ),
                        choiceChip(
                          ReaderFontOption.serif,
                          draft.fontOption,
                          'Serif',
                          (value) => draft = draft.copyWith(fontOption: value),
                        ),
                        choiceChip(
                          ReaderFontOption.mono,
                          draft.fontOption,
                          'Mono',
                          (value) => draft = draft.copyWith(fontOption: value),
                        ),
                      ],
                    ),
                    sectionTitle('레이아웃'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        choiceChip(
                          ReaderPageLayoutMode.auto,
                          draft.pageLayoutMode,
                          '자동',
                          (value) =>
                              draft = draft.copyWith(pageLayoutMode: value),
                        ),
                        choiceChip(
                          ReaderPageLayoutMode.single,
                          draft.pageLayoutMode,
                          '1페이지',
                          (value) =>
                              draft = draft.copyWith(pageLayoutMode: value),
                        ),
                        choiceChip(
                          ReaderPageLayoutMode.double,
                          draft.pageLayoutMode,
                          '2페이지',
                          (value) =>
                              draft = draft.copyWith(pageLayoutMode: value),
                        ),
                      ],
                    ),
                    sectionTitle(
                      '줄 간격: ${draft.lineHeight.toStringAsFixed(2)}',
                    ),
                    Slider(
                      value: draft.lineHeight,
                      min: 1.3,
                      max: 2.2,
                      divisions: 9,
                      onChanged: (value) => setModalState(
                        () => draft = draft.copyWith(lineHeight: value),
                      ),
                    ),
                    sectionTitle('좌우 여백: ${draft.horizontalPadding.round()}'),
                    Slider(
                      value: draft.horizontalPadding,
                      min: 10,
                      max: 34,
                      divisions: 12,
                      onChanged: (value) => setModalState(
                        () => draft = draft.copyWith(horizontalPadding: value),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('화면 꺼짐 방지'),
                      value: draft.keepScreenOn,
                      onChanged: (value) => setModalState(
                        () => draft = draft.copyWith(keepScreenOn: value),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, draft),
                        child: const Text('적용'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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

    await _settingsRepository.save(result);
    await _applyWakelock();

    final viewport = _lastViewport;
    if (viewport != null) {
      _ensurePagination(viewport, force: true);
    }
  }

  void _setFontPreset(bool large) {
    final target = large ? _fontSizeLarge : _fontSizeNormal;
    if ((_settings.fontSize - target).abs() < 0.01) {
      return;
    }

    final next = _settings.copyWith(fontSize: target);
    setState(() {
      _settings = next;
      _lastPaginationSignature = null;
    });
    unawaited(_settingsRepository.save(next));

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

  Widget _buildBody(_ReaderPalette palette) {
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
        final doubleMode = _isDoublePageMode(viewport);
        final rightPage = _pageIndex + 1;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _handleTapNavigation(details, viewport),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
                child: doubleMode
                    ? Row(
                        children: [
                          Expanded(
                            child: _PagePane(
                              text: _pages![_pageIndex],
                              style: style,
                              palette: palette,
                              horizontalPadding: _settings.horizontalPadding,
                            ),
                          ),
                          Container(
                            width: _doublePageGap,
                            color: palette.background,
                            alignment: Alignment.center,
                            child: Container(width: 1, color: palette.divider),
                          ),
                          Expanded(
                            child: rightPage < _totalPages
                                ? _PagePane(
                                    text: _pages![rightPage],
                                    style: style,
                                    palette: palette,
                                    horizontalPadding:
                                        _settings.horizontalPadding,
                                  )
                                : _PagePane(
                                    text: '',
                                    style: style,
                                    palette: palette,
                                    horizontalPadding:
                                        _settings.horizontalPadding,
                                  ),
                          ),
                        ],
                      )
                    : _PagePane(
                        text: _pages![_pageIndex],
                        style: style,
                        palette: palette,
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

  Widget _buildBottomControlPanel(_ReaderPalette palette) {
    final pageMax = math.max(0.0, (_totalPages - 1).toDouble());

    return Container(
      color: palette.panel,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  '$_displayPage/$_totalPages',
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _pageIndex.toDouble().clamp(0, pageMax),
                  min: 0,
                  max: pageMax,
                  onChanged: _totalPages <= 1
                      ? null
                      : (value) {
                          _goToPage(value.round());
                        },
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  '${(_progressRatio * 100).round()}%',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          if (_controlsExpanded)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _goPrev,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '이전 페이지',
                  ),
                  IconButton(
                    onPressed: _goNext,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '다음 페이지',
                  ),
                  IconButton(
                    onPressed: _toggleCurrentBookmark,
                    icon: Icon(
                      _bookmarks.contains(_pageIndex)
                          ? Icons.bookmark
                          : Icons.bookmark_border,
                    ),
                    tooltip: '북마크',
                  ),
                  IconButton(
                    onPressed: _openJumpDialog,
                    icon: const Icon(Icons.pin),
                    tooltip: '페이지 이동',
                  ),
                  IconButton(
                    onPressed: _openSearchDialog,
                    icon: const Icon(Icons.search),
                    tooltip: '검색',
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('기본'),
                    selected:
                        (_settings.fontSize - _fontSizeNormal).abs() < 0.01,
                    onSelected: (_) => _setFontPreset(false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('큰글'),
                    selected:
                        (_settings.fontSize - _fontSizeLarge).abs() < 0.01,
                    onSelected: (_) => _setFontPreset(true),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          if (_activeQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _queryPages.isEmpty
                    ? '검색어: "$_activeQuery" (결과 없음)'
                    : '검색어: "$_activeQuery" (${_queryCursor + 1}/${_queryPages.length})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _PagePane extends StatelessWidget {
  const _PagePane({
    required this.text,
    required this.style,
    required this.palette,
    required this.horizontalPadding,
  });

  final String text;
  final TextStyle style;
  final _ReaderPalette palette;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.background,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      alignment: Alignment.topLeft,
      child: text.trim().isEmpty
          ? const SizedBox.shrink()
          : SelectableText(text, style: style),
    );
  }
}

class _ReaderPalette {
  const _ReaderPalette({
    required this.background,
    required this.text,
    required this.panel,
    required this.divider,
  });

  final Color background;
  final Color text;
  final Color panel;
  final Color divider;
}
