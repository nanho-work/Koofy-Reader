import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_coordinator.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';

import 'native_reader_store_test.dart' show checkpoint;

class FakeGateway implements ReaderGateway {
  final controller = StreamController<ReaderEvent>.broadcast(sync: true);
  final pending = <ReaderEvent>[];
  final acknowledged = <String>[];
  ReaderLaunchRequest? request;
  Future<void> Function()? beforeAcknowledge;
  @override
  Stream<ReaderEvent> get events => controller.stream;
  @override
  Future<void> open(ReaderLaunchRequest request) async {
    this.request = request;
  }

  @override
  Future<void> close(String sessionId) async {}
  @override
  Future<List<ReaderEvent>> pendingCheckpoints() async => [...pending];
  @override
  Future<void> acknowledge(String sessionId, int sequence) async {
    await beforeAcknowledge?.call();
    acknowledged.add('$sessionId:$sequence');
  }

  @override
  Future<void> goTo(String sessionId, String locatorJson) async {}
  @override
  Future<void> applyPreferences(
    String sessionId,
    ReaderPreferences preferences,
  ) async {}
}

void main() {
  late FakeGateway gateway;
  late NativeReaderStore store;
  late NativeReaderCoordinator coordinator;
  setUp(() {
    gateway = FakeGateway();
    store = NativeReaderStore(NativeDatabase.memory());
    coordinator = NativeReaderCoordinator(gateway: gateway, store: store);
  });
  tearDown(() async {
    await coordinator.dispose();
    await gateway.controller.close();
  });

  ReaderEvent issue(String book) => ReaderEvent(
    protocolVersion: 1,
    sessionId: 'broken-file',
    sessionGeneration: 0,
    publicationId: book,
    contentRevision: '',
    sequence: 0,
    kind: 'recoveryIssue',
    message: 'damaged',
  );

  test(
    'damaged journal for another book does not prevent healthy recovery and opening',
    () async {
      final session = await store.beginSession('book', 'r1');
      gateway.pending.addAll([
        issue('damaged'),
        checkpoint(session, href: 'healthy.xhtml'),
      ]);
      await coordinator.open(
        publicationId: 'book',
        contentRevision: 'r1',
        filePath: '/book.epub',
        title: 'book',
      );
      expect(gateway.request!.initialLocatorJson, contains('healthy.xhtml'));
      expect(gateway.acknowledged, ['${session.id}:1']);
    },
  );
  test(
    'unknown session for another book remains unacknowledged but does not block opening',
    () async {
      gateway.pending.add(
        checkpoint(const ReaderSessionIdentity(id: 'missing', generation: 99))
          ..publicationId = 'other',
      );
      await coordinator.open(
        publicationId: 'book',
        contentRevision: 'r1',
        filePath: '/book.epub',
        title: 'book',
      );
      expect(gateway.request, isNotNull);
      expect(gateway.acknowledged, isEmpty);
    },
  );
  test(
    'own and unknown damaged records block safely after recovering healthy books',
    () async {
      final session = await store.beginSession('book', 'r1');
      gateway.pending.addAll([
        issue(''),
        checkpoint(session, href: 'healthy.xhtml'),
      ]);
      await expectLater(
        coordinator.open(
          publicationId: 'book',
          contentRevision: 'r1',
          filePath: '/book.epub',
          title: 'book',
        ),
        throwsStateError,
      );
      expect(gateway.request, isNull);
      expect(gateway.acknowledged, ['${session.id}:1']);
      gateway.pending.clear();
      gateway.pending.add(issue('book'));
      await expectLater(
        coordinator.open(
          publicationId: 'book',
          contentRevision: 'r1',
          filePath: '/book.epub',
          title: 'book',
        ),
        throwsStateError,
      );
      await expectLater(coordinator.recoverCheckpoints(), throwsStateError);
    },
  );

  test(
    'backup recovers pending native checkpoints without opening a book',
    () async {
      final session = await store.beginSession('book', 'r1');
      gateway.pending.add(
        checkpoint(session, href: 'latest.xhtml')..preferences!.theme = 'dark',
      );
      await coordinator.recoverCheckpoints();
      expect(gateway.request, isNull);
      expect(coordinator.activeSessionId, isNull);
      final backup = await store.exportBackup({'book'});
      expect(
        (backup['positions'] as List).single['locator'],
        contains('latest.xhtml'),
      );
      expect(gateway.acknowledged, ['${session.id}:1']);
    },
  );

  test(
    'changed content revision cannot silently restart a previously read book',
    () async {
      final old = await store.beginSession('book', 'r1');
      await store.acceptCheckpoint(checkpoint(old, href: 'old.xhtml'));
      await expectLater(
        coordinator.open(
          publicationId: 'book',
          contentRevision: 'r2',
          filePath: '/changed.epub',
          title: 'Book',
        ),
        throwsStateError,
      );
      expect(gateway.request, isNull);
      expect(
        (await store.loadPosition('book', 'r1')).locatorJson,
        contains('old.xhtml'),
      );
      expect(
        (await store.loadPosition('book', 'r2')).previousRevisionExists,
        isTrue,
      );
    },
  );

  test(
    'pending checkpoint commits before acknowledgement and before new session opens',
    () async {
      final old = await store.beginSession('book', 'r1');
      gateway.pending.add(
        checkpoint(old, href: 'recovered.xhtml')
          ..preferences!.pageTurnStyle = 'curl',
      );
      gateway.beforeAcknowledge = () async {
        expect(
          (await store.loadPosition('book', 'r1')).preferences.pageTurnStyle,
          'curl',
        );
        expect(
          (await store.loadPosition('book', 'r1')).locatorJson,
          contains('recovered.xhtml'),
        );
        expect(gateway.request, isNull);
      };
      await coordinator.open(
        publicationId: 'book',
        contentRevision: 'r1',
        filePath: '/prepared.epub',
        title: 'Book',
      );
      expect(gateway.request!.initialLocatorJson, contains('recovered.xhtml'));
      expect(gateway.request!.preferences.pageTurnStyle, 'curl');
      expect(gateway.request!.sessionGeneration, greaterThan(old.generation));
      expect(gateway.acknowledged, hasLength(1));
    },
  );

  test(
    'invalid checkpoint is not acknowledged or used to open a new session',
    () async {
      gateway.pending.add(
        checkpoint(const ReaderSessionIdentity(id: 'missing', generation: 99)),
      );
      await expectLater(
        coordinator.open(
          publicationId: 'book',
          contentRevision: 'r1',
          filePath: '/prepared.epub',
          title: 'Book',
        ),
        throwsFormatException,
      );
      expect(gateway.acknowledged, isEmpty);
      expect(gateway.request, isNull);
    },
  );

  test(
    'one active session and serialized events preserve newest state',
    () async {
      final id = await coordinator.open(
        publicationId: 'book',
        contentRevision: 'r1',
        filePath: '/prepared.epub',
        title: 'Book',
      );
      await expectLater(
        coordinator.open(
          publicationId: 'other',
          contentRevision: 'r1',
          filePath: '/other.epub',
          title: 'Other',
        ),
        throwsStateError,
      );
      final session = ReaderSessionIdentity(
        id: id,
        generation: gateway.request!.sessionGeneration,
      );
      gateway.controller.add(
        checkpoint(session, sequence: 4, href: 'latest.xhtml'),
      );
      gateway.controller.add(
        checkpoint(session, sequence: 3, href: 'late.xhtml'),
      );
      await coordinator.flush();
      expect(
        (await store.loadPosition('book', 'r1')).locatorJson,
        contains('latest.xhtml'),
      );
      expect(gateway.acknowledged, hasLength(2));
    },
  );

  test(
    'native error context is delivered without being committed or acknowledged',
    () async {
      final id = await coordinator.open(
        publicationId: 'book',
        contentRevision: 'r1',
        filePath: '/prepared.epub',
        title: 'Book',
      );
      final session = ReaderSessionIdentity(
        id: id,
        generation: gateway.request!.sessionGeneration,
      );
      final events = <ReaderEvent>[];
      final errors = <Object>[];
      final eventSubscription = coordinator.events.listen(events.add);
      final errorSubscription = coordinator.errors.listen(errors.add);
      gateway.controller.add(checkpoint(session)..kind = 'error');
      await coordinator.flush();
      await Future<void>.delayed(Duration.zero);
      expect(events.single.kind, 'error');
      expect(errors, isEmpty);
      expect(gateway.acknowledged, isEmpty);
      expect((await store.loadPosition('book', 'r1')).locatorJson, isNull);
      await eventSubscription.cancel();
      await errorSubscription.cancel();
    },
  );

  test(
    'failed event keeps native checkpoint and does not break later events',
    () async {
      final id = await coordinator.open(
        publicationId: 'book',
        contentRevision: 'r1',
        filePath: '/prepared.epub',
        title: 'Book',
      );
      final session = ReaderSessionIdentity(
        id: id,
        generation: gateway.request!.sessionGeneration,
      );
      final errors = <Object>[];
      final subscription = coordinator.errors.listen(errors.add);
      gateway.controller.add(checkpoint(session)..locatorJson = '{}');
      gateway.controller.add(
        checkpoint(session, sequence: 2, href: 'valid.xhtml'),
      );
      await coordinator.flush();
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(gateway.acknowledged, ['$id:2']);
      await subscription.cancel();
    },
  );
}
