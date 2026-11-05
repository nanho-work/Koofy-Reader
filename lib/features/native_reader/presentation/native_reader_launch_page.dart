import 'package:koofy_reader/features/notifications/reader_notifications.dart';
import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'package:koofy_reader/features/reading_diary/data/reading_diary.dart';
import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/native_reader/application/next_reading.dart';
import 'dart:io';
import 'package:koofy_reader/features/fonts/data/personal_fonts.dart';
import 'package:koofy_reader/features/fonts/presentation/personal_fonts_page.dart';
import 'dart:async';
import 'package:koofy_reader/features/settings/data/reader_cover_settings.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/ads/config/levelplay_ids.dart';
import 'package:koofy_reader/features/ads/data/levelplay_service.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_coordinator.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';

class NativeReaderLaunchPage extends ConsumerStatefulWidget {
  const NativeReaderLaunchPage({
    super.key,
    required this.book,
    this.initialLocatorJson,
    this.initialContentRevision,
  }) : assert((initialLocatorJson == null) == (initialContentRevision == null));
  final Book book;
  final String? initialLocatorJson;
  final String? initialContentRevision;

  @override
  ConsumerState<NativeReaderLaunchPage> createState() =>
      _NativeReaderLaunchPageState();
}

class _NativeReaderLaunchPageState
    extends ConsumerState<NativeReaderLaunchPage> {
  NativeReaderCoordinator? _coordinator;
  StreamSubscription<ReaderEvent>? _events;
  StreamSubscription<Object>? _errors;
  String? _error;
  String _status = tr("책을 준비하고 있습니다…");
  bool _launching = false;
  bool _initialLocationConsumed = false;
  bool _leaveRequested = false;
  bool _closed = false;
  bool _popScheduled = false;
  late Book _book = widget.book;
  Book? _nextBook;
  bool _continuing = false;
  bool _catalogStandalone = false;
  bool _personalGroup = false;
  NextReading? _knownNext;
  String? _knownNextFor;
  String? _continuationDownloadKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  Future<void> _open() async {
    if (_launching) return;
    setState(() {
      _launching = true;
      _leaveRequested = false;
      _error = null;
      _closed = false;
    });
    try {
      final services = await ref.read(nativeReaderServicesProvider.future);
      if (!mounted || _leaveRequested) return;
      _coordinator = services.coordinator;
      await _events?.cancel();
      await _errors?.cancel();
      if (!mounted || _leaveRequested) return;
      _events = services.coordinator.events.listen(_onEvent);
      _errors = services.coordinator.errors.listen((error) {
        if (mounted) {
          setState(
            () => _error = tr("읽기 기록 저장을 확인하지 못했습니다. 다시 열면 복구를 시도합니다.\n{0}", [
              error,
            ]),
          );
        }
      });
      final showCover = await ref.read(readerCoverEnabledProvider.future);
      if (!mounted || _leaveRequested) return;
      final publication = await services.preparer.prepare(
        book: _book,
        showRegisteredCover: showCover,
      );
      if (!mounted || _leaveRequested) return;
      _nextBook = null;
      _catalogStandalone = false;
      _personalGroup = false;
      if (_book.catalogMetadata != null) {
        try {
          final source = CatalogItem.fromJson(_book.catalogMetadata!);
          if (source.bookId == _book.id) {
            _catalogStandalone = source.seriesId == null;
            _nextBook = (await NextReadingResolver.installedSuccessor(
              source,
              await ref.read(booksProvider.future),
            ))?.book;
          }
        } catch (_) {
          /* Legacy metadata must not prevent opening a local book. */
        }
      }
      Book? diaryGroup;
      try {
        final groups = await ref.read(bookGroupsProvider.future);
        if (!mounted || _leaveRequested) return;
        final books = await ref.read(booksProvider.future);
        for (final group in groups) {
          final index = group.bookIds.indexOf(_book.id);
          if (index >= 0) diaryGroup ??= group.displayBook;
          if (index >= 0 && !group.id.startsWith('group_monthly_')) {
            _personalGroup = true;
            _nextBook = null;
            if (index + 1 < group.bookIds.length) {
              final nextId = group.bookIds[index + 1];
              final next = books.where((book) => book.id == nextId).firstOrNull;
              if (next != null &&
                  (!next.isLocalFile ||
                      (next.localPath != null &&
                          await File(next.localPath!).exists()))) {
                _nextBook = next;
              }
            }
            break;
          }
        }
      } catch (_) {
        // Broken optional group metadata must not prevent reading this book.
        _nextBook = null;
      }
      if (!mounted || _leaveRequested) return;
      setState(() => _status = tr("읽던 위치를 불러오고 있습니다…"));
      // Read storage afresh on every launch, including after earning a reward.
      final ads = await ref.read(adRepositoryProvider).getState();
      // Ad initialization must not delay opening an offline book.
      final adsReady = await ref
          .refresh(levelPlayReadyProvider.future)
          .timeout(const Duration(seconds: 1), onTimeout: () => false);
      if (!mounted || _leaveRequested) return;
      final diaryBook = await DiaryBook.snapshot(_book, group: diaryGroup);
      if (!mounted || _leaveRequested) return;
      // Ask while the Flutter host Activity is still foreground. Android's
      // messaging plugin cannot reliably request from behind ReaderActivity.
      try {
        await ref.read(readerNotificationsProvider).firstReading();
      } catch (_) {
        /* Optional notifications never prevent reading. */
      }
      if (!mounted || _leaveRequested) return;
      final known = _knownNextFor == _book.id ? _knownNext : null;
      final noFollowing =
          known?.kind == NextReadingKind.waiting ||
          known?.kind == NextReadingKind.completed;
      await services.coordinator.open(
        diaryBook: diaryBook,
        publicationId: publication.publicationId,
        contentRevision: publication.contentRevision,
        filePath: publication.filePath,
        title: publication.title,
        nextBookTitle:
            _nextBook?.title ??
            (NextReadingResolver.hasRemoteSource(_book) &&
                    !_personalGroup &&
                    !_catalogStandalone &&
                    !noFollowing
                ? tr('다음 회차 확인')
                : null),
        nextBookLabel: _nextBook != null
            ? tr('다음 회차 읽기')
            : known?.kind == NextReadingKind.download
            ? tr('다음 회차 무료로 읽기')
            : known?.kind == NextReadingKind.upcoming
            ? tr('공개 예정')
            : tr('다음 회차 확인'),
        endOfBookMessage: known?.kind == NextReadingKind.waiting
            ? tr('다음 회차를 기다려 주세요')
            : _nextBook != null ||
                  (NextReadingResolver.hasRemoteSource(_book) &&
                      !_personalGroup &&
                      !_catalogStandalone &&
                      !noFollowing)
            ? null
            : tr(_personalGroup ? '묶음의 마지막 회차입니다' : '마지막 회차입니다'),
        bannerAdUnitId: adsReady ? LevelPlayIds.readerBanner : null,
        adHiddenUntilEpochMs: ads.hiddenUntil?.millisecondsSinceEpoch,
        resolveInitialLocator: (position) =>
            _resolvePosition(services, publication, position),
      );
    } on _LaunchCancelled {
      if (mounted) _leaveRequested = true;
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = tr("책을 열지 못했습니다.\n{0}", [localizedError(error)]),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _launching = false);
        // A back request may arrive while the coordinator is recovering its
        // journal or allocating a session. Finish that open before closing it.
        if (_leaveRequested) await _leave();
      }
    }
  }

  Future<String?> _resolvePosition(
    NativeReaderServices services,
    PreparedReadingPublication publication,
    StoredReaderPosition position,
  ) async {
    if (!mounted || _leaveRequested) throw const _LaunchCancelled();
    if (!_initialLocationConsumed &&
        _book.id == widget.book.id &&
        widget.initialLocatorJson != null) {
      if (widget.initialContentRevision != publication.contentRevision) {
        throw StateError(tr("책의 내용이 변경되었습니다. 이전 기록을 다시 확인해 주세요."));
      }
      return publication.restoreLocator(widget.initialLocatorJson);
    }
    // Journal recovery has already run inside open(). A recovered native record
    // always takes precedence; a legacy archive can never overwrite it.
    if (position.locatorJson != null) {
      return publication.restoreLocator(position.locatorJson);
    }
    if (position.previousRevisionExists) {
      final start = await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderAlertDialog(
          title: Text(tr("책의 내용이 변경되었습니다")),
          content: Text(
            tr(
              "이전 버전의 읽기 기록은 보존했습니다. 변경된 본문에는 같은 위치를 적용할 수 없습니다. 처음 열고 목차에서 읽던 곳을 찾아 주세요.",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr("서재로")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr("변경된 책 열기")),
            ),
          ],
        ),
      );
      if (!mounted || _leaveRequested || start != true) {
        throw const _LaunchCancelled();
      }
      return null;
    }
    final record = await ref
        .read(legacyReaderArchiveProvider)
        .loadBook(_book.id, support: services.supportDirectory);
    if (!mounted || _leaveRequested) throw const _LaunchCancelled();
    if (record == null || !record.hasProgress) return null;
    final map = publication.textMap;
    final offset = record.offset;
    final candidate = offset == null ? null : map?.locatorAt(offset);
    if (candidate != null && record.cachedText == map?.text) return candidate;
    final ratio = record.progress?.positionRatio;
    final choice = await showReaderDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ReaderAlertDialog(
        title: Text(tr("이전 읽기 위치 확인")),
        content: SingleChildScrollView(
          child: Text(
            [
              tr("이전 기록은 보존했습니다. 현재 본문에서 같은 위치임을 확인할 수 없어 자동으로 이동하지 않습니다."),
              '\n\n',
              ratio == null
                  ? tr('진행률을 확인할 수 없습니다.')
                  : tr('이전 진행률: {0}%', [(ratio * 100).floor()]),
              '\n',
              record.excerpt(offset),
              if (candidate != null)
                '\n\n${tr('문자 위치로 계산한 후보를 직접 확인할 수 있습니다.')}',
            ].join(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: Text(tr("서재로")),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'start'),
            child: Text(tr("처음 열고 목차에서 찾기")),
          ),
          if (candidate != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'candidate'),
              child: Text(tr("후보 위치 확인")),
            ),
        ],
      ),
    );
    if (!mounted || _leaveRequested || choice == null || choice == 'cancel') {
      throw const _LaunchCancelled();
    }
    return choice == 'candidate' ? candidate : null;
  }

  void _onEvent(ReaderEvent event) {
    if (!mounted || event.publicationId != _book.id) return;
    switch (event.kind) {
      case 'ready':
        ReaderAnalytics.instance.bookOpened(
          bundled: !_book.isLocalFile,
          guide: _book.isReaderGuide,
        );
        _initialLocationConsumed = true;
        setState(() => _status = tr("책을 읽고 있습니다."));
      case 'error':
        setState(() => _error = event.message ?? tr("독서 화면에서 오류가 발생했습니다."));
      case 'closed':
        setState(() => _closed = true);
        ref.invalidate(nativeLibraryPositionsProvider);
        if (_error == null &&
            event.message == 'manageFonts' &&
            !_leaveRequested) {
          unawaited(_manageFonts());
        } else if (_error == null &&
            (event.message == 'downloadSeries' ||
                event.message == 'nextBook') &&
            (_nextBook != null || NextReadingResolver.hasRemoteSource(_book)) &&
            !_leaveRequested) {
          unawaited(_continueReading());
        } else if (_error == null) {
          _returnToLibrary();
        }
    }
  }

  Future<void> _continueReading() async {
    if (_continuing || _leaveRequested) return;
    setState(() {
      _continuing = true;
      _status = tr('다음 회차를 확인하고 있습니다…');
    });
    Book? next;
    var retry = false;
    try {
      await _coordinator?.flush();
      if (!mounted || _leaveRequested) return;
      final books = await ref.read(booksProvider.future);
      final groups = await ref.read(bookGroupsProvider.future);
      final result = await NextReadingResolver(
        ref.read(readerCatalogProvider),
      ).resolve(_book, books, groups);
      if (!mounted || _leaveRequested) return;
      _knownNext = result;
      _knownNextFor = _book.id;
      switch (result.kind) {
        case NextReadingKind.local:
          next = result.book;
        case NextReadingKind.download:
          final item = result.item!;
          final accepted = await showReaderDialog<bool>(
            context: context,
            builder: (dialogContext) => ReaderAlertDialog(
              title: Text(tr('다음 회차 무료로 읽기')),
              content: Text(
                tr('{0}을 무료로 다운로드한 뒤 바로 엽니다.', [
                  item.episodeNumber != null && item.episodeTitle != null
                      ? tr('{0}화 · {1}', [
                          item.episodeNumber,
                          item.episodeTitle,
                        ])
                      : item.title,
                ]),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(tr('취소')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(tr('다운로드 후 읽기')),
                ),
              ],
            ),
          );
          if (accepted != true || !mounted || _leaveRequested) break;
          setState(() {
            _status = tr('다음 회차를 다운로드하고 있습니다…');
            _continuationDownloadKey = catalogItemKey(item);
          });
          await ref.read(catalogDownloadProvider.notifier).download(item);
          if (!mounted || _leaveRequested) return;
          final installed = await ref.refresh(booksProvider.future);
          next = await NextReadingResolver.existingBook(item, installed);
          if (next == null) {
            throw const CatalogException('다운로드하지 못했습니다. 다시 시도해 주세요.');
          }
        case NextReadingKind.upcoming:
          final date = result.item!.releaseAt.isNotEmpty
              ? result.item!.releaseAt
              : result.item!.releaseDate;
          await _nextNotice(
            tr('공개 예정'),
            tr('{0} 공개 예정입니다. 공개 후 무료로 읽을 수 있습니다.', [
              date.replaceAll('T', ' ').replaceAll(':00+09:00', ''),
            ]),
          );
        case NextReadingKind.waiting:
          await _nextNotice(tr('다음 회차 안내'), tr('다음 회차를 기다려 주세요'));
        case NextReadingKind.completed:
          await _nextNotice(
            tr('다음 회차 안내'),
            tr(result.groupEnd ? '묶음의 마지막 회차입니다' : '마지막 회차입니다'),
          );
      }
    } catch (error) {
      if (mounted && !_leaveRequested) {
        retry =
            await showReaderDialog<bool>(
              context: context,
              builder: (dialogContext) => ReaderAlertDialog(
                title: Text(tr('다음 회차를 열지 못했습니다')),
                content: Text(
                  error is CatalogException
                      ? tr(error.message)
                      : tr('인터넷 연결을 확인하고 다시 시도해 주세요.'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(tr('현재 회차로 돌아가기')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(tr('다시 시도')),
                  ),
                ],
              ),
            ) ==
            true;
      }
    } finally {
      if (mounted) {
        setState(() {
          _continuing = false;
          _continuationDownloadKey = null;
        });
      }
    }
    if (!mounted || _leaveRequested) return;
    if (retry) {
      unawaited(_continueReading());
      return;
    }
    if (next != null) setState(() => _book = next!);
    await _open(); // Cancel/failure restores the exact saved last-page locator.
  }

  Future<void> _nextNotice(String title, String message) =>
      showReaderDialog<void>(
        context: context,
        builder: (dialogContext) => ReaderAlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr('확인')),
            ),
          ],
        ),
      );

  Future<void> _manageFonts() async {
    try {
      final services = await ref.read(nativeReaderServicesProvider.future);
      if (!mounted) return;
      final support = services.supportDirectory;
      if (support == null) throw StateError(tr("글꼴 저장소를 찾지 못했습니다."));
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PersonalFontsPage(
            store: PersonalFontStore(
              Directory('${support.path}/personal_fonts'),
            ),
            reader: services.coordinator.store,
          ),
        ),
      );
      if (mounted && !_leaveRequested) await _open();
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = tr("글꼴 관리 화면을 열지 못했습니다.\n{0}", [localizedError(error)]),
        );
      }
    }
  }

  Future<void> _leave() async {
    if (_launching) {
      setState(() {
        _leaveRequested = true;
        _status = tr("책 열기를 취소하고 있습니다…");
      });
      return;
    }
    try {
      await _coordinator?.close();
      if (mounted && (_coordinator?.activeSessionId == null || _closed)) {
        _returnToLibrary();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = tr("독서 화면을 닫지 못했습니다.\n{0}", [localizedError(error)]),
        );
      }
    }
  }

  void _returnToLibrary() {
    if (!mounted || _popScheduled) return;
    _popScheduled = true;
    // Rebuild PopScope before popping, and coalesce close callbacks with back taps.
    setState(() => _closed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    unawaited(_errors?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final download = ref.watch(catalogDownloadProvider);
    final downloadingNext =
        _continuing &&
        download.busy &&
        download.itemKey == _continuationDownloadKey;
    return PopScope(
      canPop: !_launching && (_coordinator?.activeSessionId == null || _closed),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_book.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error == null && downloadingNext)
                  LinearProgressIndicator(value: download.progress)
                else if (_error == null)
                  const CircularProgressIndicator(),
                if (downloadingNext)
                  Text('${(download.progress * 100).floor()}%'),
                const SizedBox(height: 20),
                Text(_error ?? _status, textAlign: TextAlign.center),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  if (_coordinator?.activeSessionId == null)
                    FilledButton(
                      onPressed: _launching ? null : _open,
                      child: Text(tr("다시 시도")),
                    ),
                  TextButton(onPressed: _leave, child: Text(tr("서재로 돌아가기"))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchCancelled implements Exception {
  const _LaunchCancelled();
}
