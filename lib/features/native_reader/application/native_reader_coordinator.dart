import 'dart:async';

import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';

/// Serializes DB commits independently from Flutter frame/lifecycle callbacks.
class NativeReaderCoordinator {
  NativeReaderCoordinator({required this.gateway, required this.store}) {
    _subscription = gateway.events.listen(_receive);
  }

  final ReaderGateway gateway;
  final NativeReaderStore store;
  final _events = StreamController<ReaderEvent>.broadcast();
  final _errors = StreamController<Object>.broadcast();
  late final StreamSubscription<ReaderEvent> _subscription;
  Future<void> _queue = Future<void>.value();
  bool _opening = false;
  String? _activeSessionId;

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
        if (event.kind == 'closed') _activeSessionId = null;
        _events.add(event);
      }
    });
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
    await gateway.acknowledge(event.sessionId, event.sequence);
  }

  Future<String> open({
    required String publicationId,
    required String contentRevision,
    required String filePath,
    required String title,
    String? bannerAdUnitId,
    int? adHiddenUntilEpochMs,
    String? nextBookTitle,
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
      try {
        await gateway.open(
          ReaderLaunchRequest(
            protocolVersion: 1,
            sessionId: session.id,
            sessionGeneration: session.generation,
            publicationId: publicationId,
            contentRevision: contentRevision,
            filePath: filePath,
            title: title,
            initialLocatorJson: initialLocator,
            preferences: position.preferences,
            bannerAdUnitId: bannerAdUnitId,
            adHiddenUntilEpochMs: adHiddenUntilEpochMs,
            nextBookTitle: nextBookTitle,
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

  Future<void> flush() => _queue;

  /// Backup must include the native journal even before the first book is opened.
  Future<void> recoverCheckpoints() async {
    if (_opening || _activeSessionId != null) {
      throw StateError('책을 닫은 뒤 백업을 이용해 주세요.');
    }
    _opening = true;
    try {
      await _queue;
      await _recover();
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
    await _events.close();
    await _errors.close();
    await store.close();
  }
}
