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
    Future<String?> Function(StoredReaderPosition)? resolveInitialLocator,
  }) async {
    if (_opening || _activeSessionId != null) {
      throw StateError('이미 열려 있는 책을 먼저 닫아 주세요.');
    }
    _opening = true;
    try {
      // Recovery must precede allocating a new durable session generation.
      await _queue;
      final pending = await gateway.pendingCheckpoints();
      pending.sort((a, b) {
        final generation = a.sessionGeneration.compareTo(b.sessionGeneration);
        return generation == 0 ? a.sequence.compareTo(b.sequence) : generation;
      });
      for (final event in pending) {
        await _commit(event);
      }
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

  Future<void> dispose() async {
    await _subscription.cancel();
    await _queue;
    await _events.close();
    await _errors.close();
    await store.close();
  }
}
