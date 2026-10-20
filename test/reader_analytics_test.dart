import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> drain() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'no events before consent or after withdrawal, choice survives restart',
    () async {
      final events = <String>[];
      final service = ReaderAnalytics(
        writer: (name, _) async => events.add(name),
      );
      await service.initialize();
      expect(service.choice, isNull);
      service.feature('tts_start');
      await drain();
      expect(events, isEmpty);
      await service.choose(true);
      service.feature('tts_start');
      await drain();
      expect(events, ['tts_start']);
      // A queued event must not outlive withdrawal.
      service.feature('bookmark_add');
      await service.choose(false);
      await drain();
      expect(events, ['tts_start']);
      final restarted = ReaderAnalytics(
        writer: (name, _) async => events.add(name),
      );
      await restarted.initialize();
      expect(restarted.choice, false);
      restarted.feature('tts_start');
      await drain();
      expect(events, ['tts_start']);
    },
  );

  test('only controlled parameters and public catalog IDs are sent', () async {
    final events = <Map<String, Object>>[];
    final service = ReaderAnalytics(
      writer: (name, data) async => events.add({'event': name, ...data}),
    );
    await service.initialize();
    await service.choose(true);
    service.bookImport('/private/my-secret-book.txt', 'exception with title');
    service.feature('my private title');
    service.download(kind: 'book', id: 'public_123', result: 'success');
    service.download(kind: 'font', id: '/private/font.ttf', result: 'failed');
    service.bookOpened(bundled: false, guide: false);
    await drain();
    expect(events.length, 4);
    expect(events[0]['format'], 'other');
    expect(events[0]['result'], 'failed');
    expect(events[1]['content_id'], 'public_123');
    expect(events[2].containsKey('content_id'), false);
    expect(events[3]['source'], 'local');
    expect(events.toString(), isNot(contains('private')));
  });

  test('analytics failures do not escape to file operations', () async {
    final service = ReaderAnalytics(
      writer: (_, _) async => throw StateError('network'),
    );
    await service.initialize();
    await service.choose(true);
    service.download(kind: 'font', id: 'font_1', result: 'success');
    await drain();
  });
}
