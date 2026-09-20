library;

import 'dart:async';

import 'src/reader_api.g.dart';

export 'src/reader_api.g.dart'
    show ReaderEvent, ReaderLaunchRequest, ReaderPreferences;

/// One app-owned gateway. Native callbacks are installed before any book opens.
/// Events are not persistence acknowledgements; callers ACK only after commit.
abstract interface class ReaderGateway {
  Stream<ReaderEvent> get events;
  Future<void> open(ReaderLaunchRequest request);
  Future<void> close(String sessionId);
  Future<List<ReaderEvent>> pendingCheckpoints();
  Future<void> acknowledge(String sessionId, int sequence);
  Future<void> goTo(String sessionId, String locatorJson);
  Future<void> applyPreferences(
    String sessionId,
    ReaderPreferences preferences,
  );
}

class NativeReaderGateway implements ReaderGateway, ReaderFlutterApi {
  NativeReaderGateway() {
    ReaderFlutterApi.setUp(this);
  }

  final ReaderHostApi _host = ReaderHostApi();
  final StreamController<ReaderEvent> _events =
      StreamController<ReaderEvent>.broadcast();

  @override
  Stream<ReaderEvent> get events => _events.stream;

  @override
  void onEvent(ReaderEvent event) => _events.add(event);

  @override
  Future<void> open(ReaderLaunchRequest request) => _host.openReader(request);

  @override
  Future<void> close(String sessionId) => _host.closeReader(sessionId);

  @override
  Future<List<ReaderEvent>> pendingCheckpoints() => _host.pendingCheckpoints();

  @override
  Future<void> acknowledge(String sessionId, int sequence) =>
      _host.acknowledgeCheckpoint(sessionId, sequence);

  @override
  Future<void> goTo(String sessionId, String locatorJson) =>
      _host.goTo(sessionId, locatorJson);

  @override
  Future<void> applyPreferences(
    String sessionId,
    ReaderPreferences preferences,
  ) => _host.applyPreferences(sessionId, preferences);
}

/// Update an already-open native reader after a delayed reward callback.
Future<void> updateNativeReaderAdHiddenUntil(int? epochMs) =>
    ReaderHostApi().updateAdHiddenUntil(epochMs);
