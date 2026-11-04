import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_coordinator.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/reading_diary/data/reading_diary.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';
import 'native_reader_coordinator_test.dart' show FakeGateway;
import 'library_backup_test.dart' show MemoryBackupStorage;

class TestClock extends Stopwatch {
  int ms = 0;
  bool running = false;
  void advance(int seconds) {
    if (running) ms += seconds * 1000;
  }

  @override
  Duration get elapsed => Duration(milliseconds: ms);
  @override
  bool get isRunning => running;
  @override
  void start() => running = true;
  @override
  void stop() => running = false;
  @override
  void reset() => ms = 0;
}

void main() {
  test(
    'counts only ready, foreground and uncovered viewer; ignores replayed sessions',
    () async {
      SharedPreferences.setMockInitialValues({});
      final gateway = FakeGateway();
      final clock = TestClock();
      final diary = ReadingDiary(MemoryBackupStorage());
      final coordinator = NativeReaderCoordinator(
        gateway: gateway,
        store: NativeReaderStore(NativeDatabase.memory()),
        diary: diary,
        readingClock: clock,
        now: () => DateTime(2026, 11, 2, 12),
      );
      await coordinator.open(
        publicationId: 'book',
        contentRevision: 'r',
        filePath: '/book.epub',
        title: 'Book',
        diaryBook: const DiaryBook(id: 'book', title: 'Book'),
      );
      var seq = 1;
      Future<void> emit(String kind, [String? message]) async {
        final r = gateway.request!;
        gateway.controller.add(
          ReaderEvent(
            protocolVersion: 1,
            sessionId: r.sessionId,
            sessionGeneration: r.sessionGeneration,
            publicationId: 'book',
            contentRevision: 'r',
            sequence: seq++,
            kind: kind,
            message: message,
          ),
        );
        await coordinator.flush();
      }

      await emit('usage', 'reading_resume');
      clock.advance(100);
      expect(clock.running, isFalse);
      await emit('ready');
      clock.advance(10);
      await emit('usage', 'reading_overlay_pause');
      clock.advance(100);
      await emit('usage', 'reading_pause');
      await emit('usage', 'reading_overlay_resume');
      clock.advance(100);
      expect(clock.running, isFalse);
      await emit('usage', 'reading_resume');
      clock.advance(20);
      await emit('closed');
      clock.advance(100);
      expect((await diary.load()).single.duration.inSeconds, 30);
      await coordinator.dispose();
      await gateway.controller.close();
    },
  );
}
