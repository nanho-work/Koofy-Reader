import 'dart:async';
import 'package:koofy_reader/features/ads/data/levelplay_service.dart';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_coordinator.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader/features/native_reader/presentation/native_reader_launch_page.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/native_reader/data/text_publication_map.dart';
import 'package:koofy_reader/core/utils/hash_utils.dart';
import 'dart:convert';

class _DeferredPreparer extends ReadingPublicationPreparer {
  _DeferredPreparer() : super(storageDirectory: Directory.systemTemp);
  final result = Completer<PreparedReadingPublication>();
  int calls = 0;
  final publications = <String, PreparedReadingPublication>{};

  @override
  Future<PreparedReadingPublication> prepare({required Book book}) {
    calls++;
    if (publications.containsKey(book.id)) {
      return Future.value(publications[book.id]);
    }
    return result.future;
  }

  void complete({TextPublicationMap? textMap}) => result.complete(
    PreparedReadingPublication(
      publicationId: 'book',
      contentRevision: 'revision',
      filePath: '/prepared.epub',
      title: 'Book',
      textMap: textMap,
    ),
  );
}

class _LaunchGateway implements ReaderGateway {
  final controller = StreamController<ReaderEvent>.broadcast(sync: true);
  final recovery = Completer<List<ReaderEvent>>();
  int recoveryCalls = 0;
  int openCalls = 0;
  int closeCalls = 0;
  ReaderLaunchRequest? request;

  @override
  Stream<ReaderEvent> get events => controller.stream;
  @override
  Future<List<ReaderEvent>> pendingCheckpoints() {
    recoveryCalls++;
    return recovery.future;
  }

  @override
  Future<void> open(ReaderLaunchRequest request) async {
    this.request = request;
    openCalls++;
  }

  @override
  Future<void> close(String sessionId) async {
    closeCalls++;
    final active = request!;
    controller.add(
      ReaderEvent(
        protocolVersion: 1,
        sessionId: active.sessionId,
        sessionGeneration: active.sessionGeneration,
        publicationId: active.publicationId,
        contentRevision: active.contentRevision,
        sequence: 1,
        kind: 'closed',
      ),
    );
  }

  @override
  Future<void> acknowledge(String sessionId, int sequence) async {}
  @override
  Future<void> goTo(String sessionId, String locatorJson) async {}
  @override
  Future<void> applyPreferences(
    String sessionId,
    ReaderPreferences preferences,
  ) async {}
}

void main() {
  final book = Book.asset(
    id: 'book',
    title: 'Book',
    author: '',
    description: '',
    assetPath: 'unused.txt',
  );
  late _DeferredPreparer preparer;
  late _LaunchGateway gateway;
  late NativeReaderCoordinator coordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    preparer = _DeferredPreparer();
    gateway = _LaunchGateway();
    coordinator = NativeReaderCoordinator(
      gateway: gateway,
      store: NativeReaderStore(NativeDatabase.memory()),
    );
  });
  tearDown(() async {
    await coordinator.dispose();
    await gateway.controller.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    Directory? support,
    List<Book>? library,
    List<BookGroup>? groups,
  }) async {
    final services = NativeReaderServices(
      preparer: preparer,
      coordinator: coordinator,
      supportDirectory: support,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (library != null)
            booksProvider.overrideWith((ref) async => library),
          if (groups != null)
            bookGroupsProvider.overrideWith((ref) async => groups),
          levelPlayReadyProvider.overrideWith((ref) async => true),
          nativeReaderServicesProvider.overrideWith((ref) async => services),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => NativeReaderLaunchPage(book: book),
                  ),
                ),
                child: const Text('서재'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('서재'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
      // The database and gateway fixtures are created outside FakeAsync. Allow
      // their real microtasks to settle as well as advancing Flutter frames.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  testWidgets(
    'next volume preserves the old locator and opens the saved group order',
    (tester) async {
      final next = Book.asset(
        id: 'next',
        title: '제2화',
        author: '',
        description: '',
        assetPath: 'unused.txt',
      );
      preparer.complete();
      preparer.publications[next.id] = const PreparedReadingPublication(
        publicationId: 'next',
        contentRevision: 'r2',
        filePath: '/next.epub',
        title: '제2화',
      );
      gateway.recovery.complete([]);
      await mount(
        tester,
        library: [book, next],
        groups: [
          BookGroup(id: 'group_test', title: '소설', bookIds: [book.id, next.id]),
        ],
      );
      await pumpUntil(tester, () => gateway.openCalls == 1);
      expect(gateway.request!.nextBookTitle, '제2화');
      final request = gateway.request!;
      gateway.controller.add(
        ReaderEvent(
          protocolVersion: 1,
          sessionId: request.sessionId,
          sessionGeneration: request.sessionGeneration,
          publicationId: request.publicationId,
          contentRevision: request.contentRevision,
          sequence: 1,
          kind: 'closed',
          message: 'nextBook',
          locatorJson: '{"href":"saved.xhtml"}',
          preferences: defaultReaderPreferences()..theme = 'dark',
        ),
      );
      await pumpUntil(tester, () => gateway.openCalls == 2);
      expect(gateway.request!.publicationId, 'next');
      expect(gateway.request!.nextBookTitle, isNull);
      expect(gateway.request!.preferences.theme, 'dark');
      expect(
        (await tester.runAsync(
          () => coordinator.store.loadPosition('book', 'revision'),
        ))!.locatorJson,
        contains('saved.xhtml'),
      );
      expect(find.byType(NativeReaderLaunchPage), findsOneWidget);
      await gateway.close(gateway.request!.sessionId);
      await pumpUntil(
        tester,
        () => find.byType(NativeReaderLaunchPage).evaluate().isEmpty,
      );
      expect(gateway.openCalls, 2);
    },
  );

  testWidgets('reader launch forwards the saved rewarded banner expiry', (
    tester,
  ) async {
    final expiry = DateTime.now()
        .add(const Duration(hours: 5))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      AppConstants.adHideExpiryKey: expiry,
    });
    preparer.complete();
    gateway.recovery.complete([]);
    await mount(tester);
    await pumpUntil(tester, () => gateway.openCalls == 1);
    expect(gateway.request!.adHiddenUntilEpochMs, expiry);
    expect(gateway.request!.bannerAdUnitId, '2dr1bupao7hqz66b');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unconvertible legacy position never silently opens at the start',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'reader_progress_book': '{"positionRatio":0.8}',
      });
      preparer.complete();
      gateway.recovery.complete([]);
      await mount(tester);
      await pumpUntil(
        tester,
        () => find.text('이전 읽기 위치 확인').evaluate().isNotEmpty,
      );
      expect(gateway.openCalls, 0);
      expect(coordinator.activeSessionId, isNull);
      await tester.tap(find.text('서재로'));
      await pumpUntil(
        tester,
        () => find.byType(NativeReaderLaunchPage).evaluate().isEmpty,
      );
      expect(gateway.openCalls, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reader_progress_book'), '{"positionRatio":0.8}');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'verified legacy text is mapped to Readium without reusing spread start',
    (tester) async {
      final text = '한글 문장입니다. ' * 100;
      SharedPreferences.setMockInitialValues({
        'reader_progress_book':
            '{"contentOffset":500,"doublePageStartOffset":200}',
      });
      final support = Directory.systemTemp.createTempSync('cutover-launch-');
      addTearDown(() => support.delete(recursive: true));
      final cache = File(
        '${support.path}/reader_content_cache/${HashUtils.fnv1a32('book')}.json',
      );
      cache.parent.createSync(recursive: true);
      cache.writeAsStringSync(jsonEncode({'normalizedContent': text}));
      final map = TextPublicationMap(text);
      preparer.complete(textMap: map);
      gateway.recovery.complete([]);
      await mount(tester, support: support);
      await pumpUntil(tester, () => gateway.openCalls == 1);
      expect(gateway.request!.initialLocatorJson, map.locatorAt(500));
      expect(find.text('이전 읽기 위치 확인'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('back during preparation cancels launch and returns only once', (
    tester,
  ) async {
    await mount(tester);
    expect(preparer.calls, 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(NativeReaderLaunchPage), findsOneWidget);
    expect(find.text('책 열기를 취소하고 있습니다…'), findsOneWidget);
    preparer.complete();
    await pumpUntil(
      tester,
      () => find.byType(NativeReaderLaunchPage).evaluate().isEmpty,
    );
    expect(gateway.openCalls, 0);
    expect(gateway.closeCalls, 0);
    expect(find.text('서재'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'back during recovery cancels before allocating a new native session',
    (tester) async {
      preparer.complete();
      await mount(tester);
      await pumpUntil(tester, () => gateway.recoveryCalls == 1);
      expect(coordinator.activeSessionId, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(NativeReaderLaunchPage), findsOneWidget);
      // Recovering/allocating a session is the interval in which back used to
      // dispose the Flutter route and then unexpectedly open native above it.
      gateway.recovery.complete([]);
      await pumpUntil(
        tester,
        () => find.byType(NativeReaderLaunchPage).evaluate().isEmpty,
      );
      expect(gateway.openCalls, 0);
      expect(gateway.closeCalls, 0);
      expect(coordinator.activeSessionId, isNull);
      expect(find.text('서재'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
