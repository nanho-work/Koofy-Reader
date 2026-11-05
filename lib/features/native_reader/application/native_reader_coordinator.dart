import 'package:koofy_reader/features/reading_diary/data/reading_diary.dart';
import 'package:koofy_reader/core/theme/app_appearance.dart';
import 'package:koofy_reader/features/reviews/data/reader_review_service.dart';
import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'dart:async';

import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';

/// Serializes DB commits independently from Flutter frame/lifecycle callbacks.
class NativeReaderCoordinator {
  NativeReaderCoordinator({
    required this.gateway,
    required this.store,
    this.diary,
    Stopwatch? readingClock,
    DateTime Function()? now,
  }) : _readingClock = readingClock ?? Stopwatch(),
       _now = now ?? DateTime.now {
    _subscription = gateway.events.listen(_receive);
  }

  final ReadingDiary? diary;
  DiaryBook? _diaryBook;
  bool _readyForTime = false;
  bool _foreground = true;
  bool _uncovered = true;
  final ReaderGateway gateway;
  final NativeReaderStore store;
  final _events = StreamController<ReaderEvent>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  late final StreamSubscription<ReaderEvent> _subscription;
  Future<void> _queue = Future<void>.value();
  bool _opening = false;
  String? _activeSessionId;
  final Stopwatch _readingClock;
  final DateTime Function() _now;
  Timer? _readingTimer;
  void _flushReadingTime() {
    final elapsed = _readingClock.elapsed;
    final seconds = elapsed.inSeconds;
    _readingClock.reset();
    final book = _diaryBook;
    if (book != null && elapsed.inMilliseconds > 0 && diary != null) {
      unawaited(
        diary!.add(book, _now().subtract(elapsed), elapsed).catchError((
          Object error,
        ) {
          _errors.add(error);
        }),
      );
    }
    if (seconds > 0) ReaderAnalytics.instance.readingTime(seconds);
    if (elapsed.inMilliseconds > 0) {
      unawaited(ReaderReviewService.instance.addReadingTime(elapsed));
    }
  }

  Stream<ReaderEvent> get events => _events.stream;
  Stream<Object> get errors => _errors.stream;
  String? get activeSessionId => _activeSessionId;

  void _receive(ReaderEvent event) {
    _queue = _queue.then((_) async {
      try {
        if (_isCheckpoint(event)) await _commit(event);
      } catch (error) {
        // Do not ACK failed writes. Native's durable copy is kept for retry.
        _errors.add(error);
      }
      if (event.sessionId == _activeSessionId) {
        if (event.kind == 'ready') {
          _readyForTime = true;
          _readingTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
            if (_readingClock.isRunning) _flushReadingTime();
          });
          _syncReadingClock();
        }
        if (event.kind == 'usage') {
          switch (event.message) {
            case 'reading_pause':
              _foreground = false;
              _syncReadingClock();
            case 'reading_resume':
              _foreground = true;
              _syncReadingClock();
            case 'reading_overlay_pause':
              _uncovered = false;
              _syncReadingClock();
            case 'reading_overlay_resume':
              _uncovered = true;
              _syncReadingClock();
            default:
              ReaderAnalytics.instance.feature(event.message ?? '');
          }
        }
        if (event.kind == 'closed') {
          _readingTimer?.cancel();
          _readingTimer = null;
          _readyForTime = false;
          _readingClock.stop();
          _flushReadingTime();
          _activeSessionId = null;
        }
        _events.add(event);
      }
    });
  }

  void _syncReadingClock() {
    if (_readyForTime && _foreground && _uncovered) {
      _readingClock.start();
    } else {
      _readingClock.stop();
      _flushReadingTime();
    }
  }

  bool _isCheckpoint(ReaderEvent event) =>
      const {
        'ready',
        'locationChanged',
        'preferencesChanged',
        'closed',
      }.contains(event.kind) &&
      (event.locatorJson != null || event.preferences != null);

  Future<void> _commit(ReaderEvent event) async {
    await store.acceptCheckpoint(event);
    // An explicit choice in the active viewer becomes the background for the
    // next book too. Historical/replayed checkpoints must not change it.
    if (event.sessionId == _activeSessionId &&
        event.kind == 'preferencesChanged') {
      final background = (await store.loadGlobalPreferences()).theme;
      if (const ['light', 'sepia', 'dark'].contains(background) &&
          AppAppearance.instance.selection != background) {
        await AppAppearance.instance.selectBackground(background);
      }
    }
    await gateway.acknowledge(event.sessionId, event.sequence);
  }

  Future<String> open({
    required String publicationId,
    required String contentRevision,
    required String filePath,
    required String title,
    DiaryBook? diaryBook,
    String? bannerAdUnitId,
    int? adHiddenUntilEpochMs,
    String? nextBookTitle,
    String? nextBookLabel,
    String? endOfBookMessage,
    Future<String?> Function(StoredReaderPosition)? resolveInitialLocator,
  }) async {
    if (_opening || _activeSessionId != null) {
      throw StateError('이미 열려 있는 책을 먼저 닫아 주세요.');
    }
    _opening = true;
    try {
      // Recovery must precede allocating a new durable session generation.
      await _queue;
      await _recover(publicationId: publicationId);
      final position = await store.loadPosition(publicationId, contentRevision);
      if (position.previousRevisionExists && resolveInitialLocator == null) {
        throw StateError('책의 내용이 변경되었습니다. 이전 읽기 위치를 확인해 주세요.');
      }
      final initialLocator = resolveInitialLocator == null
          ? position.locatorJson
          : await resolveInitialLocator(position);
      final session = await store.beginSession(publicationId, contentRevision);
      _activeSessionId = session.id;
      _diaryBook = diaryBook;
      _readyForTime = false;
      _foreground = true;
      _uncovered = true;
      _readingClock
        ..stop()
        ..reset();
      try {
        await gateway.open(
          ReaderLaunchRequest(
            protocolVersion: 1,
            uiLanguage: AppLanguage.instance.code,
            sessionId: session.id,
            sessionGeneration: session.generation,
            publicationId: publicationId,
            contentRevision: contentRevision,
            filePath: filePath,
            title: title,
            initialLocatorJson: initialLocator,
            preferences: position.preferences..theme = 'app',
            bannerAdUnitId: bannerAdUnitId,
            adHiddenUntilEpochMs: adHiddenUntilEpochMs,
            nextBookTitle: nextBookTitle,
            nextBookLabel: nextBookLabel,
            endOfBookMessage: endOfBookMessage,
            bookmarksJson: position.bookmarksJson,
          ),
        );
      } catch (_) {
        _activeSessionId = null;
        rethrow;
      }
      return session.id;
    } finally {
      _opening = false;
    }
  }

  Future<void> close() async {
    final sessionId = _activeSessionId;
    if (sessionId != null) await gateway.close(sessionId);
  }

  Future<void> flush() async {
    await _queue;
    await diary?.flush();
  }

  /// Backup must include the native journal even before the first book is opened.
  Future<void> recoverCheckpoints() async {
    if (_opening || _activeSessionId != null) {
      throw StateError('책을 닫은 뒤 백업을 이용해 주세요.');
    }
    _opening = true;
    try {
      await _queue;
      await _recover();
      await diary?.flush();
    } finally {
      _opening = false;
    }
  }

  /// Recover healthy records even if another book has an unreadable journal.
  /// Failed records are never acknowledged or deleted. Unknown old identities
  /// still block opening: silently treating them as another book risks data loss.
  Future<void> _recover({String? publicationId}) async {
    final pending = await gateway.pendingCheckpoints();
    pending.sort((a, b) {
      final generation = a.sessionGeneration.compareTo(b.sessionGeneration);
      return generation == 0 ? a.sequence.compareTo(b.sequence) : generation;
    });
    Object? blocking;
    final failedBooks = <String>{};
    for (final event in pending) {
      if (failedBooks.contains(event.publicationId)) continue;
      try {
        if (event.kind == 'recoveryIssue') {
          throw StateError(event.message ?? '읽기 복구 기록을 확인하지 못했습니다.');
        }
        await _commit(event);
      } catch (error) {
        failedBooks.add(event.publicationId);
        if (publicationId == null ||
            event.publicationId.isEmpty ||
            publicationId == event.publicationId) {
          blocking ??= error;
        }
        _errors.add(error);
      }
    }
    if (blocking != null) throw blocking;
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _queue;
    _readingTimer?.cancel();
    _readingClock.stop();
    _flushReadingTime();
    await diary?.flush();
    await _events.close();
    await _errors.close();
    await store.close();
  }
}
