import 'dart:async';

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
  String _status = '책을 준비하고 있습니다…';
  bool _launching = false;
  bool _leaveRequested = false;
  bool _closed = false;
  bool _popScheduled = false;
  late Book _book = widget.book;
  Book? _nextBook;

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
            () => _error = '읽기 기록 저장을 확인하지 못했습니다. 다시 열면 복구를 시도합니다.\n$error',
          );
        }
      });
      final publication = await services.preparer.prepare(book: _book);
      if (!mounted || _leaveRequested) return;
      _nextBook = null;
      try {
        final groups = await ref.read(bookGroupsProvider.future);
        if (!mounted || _leaveRequested) return;
        final books = await ref.read(booksProvider.future);
        for (final group in groups) {
          final index = group.bookIds.indexOf(_book.id);
          if (index >= 0 && index + 1 < group.bookIds.length) {
            final nextId = group.bookIds[index + 1];
            _nextBook = books.where((b) => b.id == nextId).firstOrNull;
            break;
          }
        }
      } catch (_) {
        // Broken optional group metadata must not prevent reading this book.
        _nextBook = null;
      }
      if (!mounted || _leaveRequested) return;
      setState(() => _status = '읽던 위치를 불러오고 있습니다…');
      // Read storage afresh on every launch, including after earning a reward.
      final ads = await ref.read(adRepositoryProvider).getState();
      // Ad initialization must not delay opening an offline book.
      final adsReady = await ref
          .refresh(levelPlayReadyProvider.future)
          .timeout(const Duration(seconds: 1), onTimeout: () => false);
      if (!mounted || _leaveRequested) return;
      await services.coordinator.open(
        publicationId: publication.publicationId,
        contentRevision: publication.contentRevision,
        filePath: publication.filePath,
        title: publication.title,
        nextBookTitle: _nextBook?.title,
        bannerAdUnitId: adsReady ? LevelPlayIds.readerBanner : null,
        adHiddenUntilEpochMs: ads.hiddenUntil?.millisecondsSinceEpoch,
        resolveInitialLocator: (position) =>
            _resolvePosition(services, publication, position),
      );
    } on _LaunchCancelled {
      if (mounted) _leaveRequested = true;
    } catch (error) {
      if (mounted) setState(() => _error = '책을 열지 못했습니다.\n$error');
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
    if (_book.id == widget.book.id && widget.initialLocatorJson != null) {
      if (widget.initialContentRevision != publication.contentRevision) {
        throw StateError('책의 내용이 변경되었습니다. 이전 기록을 다시 확인해 주세요.');
      }
      return widget.initialLocatorJson;
    }
    // Journal recovery has already run inside open(). A recovered native record
    // always takes precedence; a legacy archive can never overwrite it.
    if (position.locatorJson != null) return position.locatorJson;
    if (position.previousRevisionExists) {
      final start = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('책의 내용이 변경되었습니다'),
          content: const Text(
            '이전 버전의 읽기 기록은 보존했습니다. 변경된 본문에는 같은 위치를 적용할 수 없습니다. 처음 열고 목차에서 읽던 곳을 찾아 주세요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('서재로'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('변경된 책 열기'),
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
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('이전 읽기 위치 확인'),
        content: SingleChildScrollView(
          child: Text(
            '이전 기록은 보존했습니다. 현재 본문에서 같은 위치임을 확인할 수 없어 자동으로 이동하지 않습니다.'
            '\n\n${ratio == null ? '진행률을 확인할 수 없습니다.' : '이전 진행률: ${(ratio * 100).floor()}%'}'
            '\n${record.excerpt(offset)}'
            '${candidate == null ? '' : '\n\n문자 위치로 계산한 후보를 직접 확인할 수 있습니다.'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('서재로'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'start'),
            child: const Text('처음 열고 목차에서 찾기'),
          ),
          if (candidate != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'candidate'),
              child: const Text('후보 위치 확인'),
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
        setState(() => _status = '책을 읽고 있습니다.');
      case 'error':
        setState(() => _error = event.message ?? '독서 화면에서 오류가 발생했습니다.');
      case 'closed':
        setState(() => _closed = true);
        ref.invalidate(nativeLibraryPositionsProvider);
        if (_error == null &&
            event.message == 'nextBook' &&
            _nextBook != null &&
            !_leaveRequested) {
          setState(() {
            _book = _nextBook!;
            _status = '다음 권을 준비하고 있습니다…';
          });
          unawaited(_open());
        } else if (_error == null) {
          _returnToLibrary();
        }
    }
  }

  Future<void> _leave() async {
    if (_launching) {
      setState(() {
        _leaveRequested = true;
        _status = '책 열기를 취소하고 있습니다…';
      });
      return;
    }
    try {
      await _coordinator?.close();
      if (mounted && (_coordinator?.activeSessionId == null || _closed)) {
        _returnToLibrary();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '독서 화면을 닫지 못했습니다.\n$error');
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
  Widget build(BuildContext context) => PopScope(
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
              if (_error == null) const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_error ?? _status, textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 16),
                if (_coordinator?.activeSessionId == null)
                  FilledButton(
                    onPressed: _launching ? null : _open,
                    child: const Text('다시 시도'),
                  ),
                TextButton(onPressed: _leave, child: const Text('서재로 돌아가기')),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _LaunchCancelled implements Exception {
  const _LaunchCancelled();
}
