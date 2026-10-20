import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/reviews/data/reader_review_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late int requests;
  late ReaderReviewService service;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 21);
    requests = 0;
    service = ReaderReviewService(
      now: () => now,
      available: () async => true,
      request: () async {
        requests++;
      },
    );
  });
  test(
    'five-hour threshold persists across service recreation and does not count idle time',
    () async {
      await service.addReadingTime(const Duration(hours: 4, minutes: 59));
      await service.maybeRequest(canShow: () => true);
      expect(requests, 0);
      now = now.add(const Duration(days: 10));
      await service.maybeRequest(canShow: () => true);
      expect(requests, 0);
      service = ReaderReviewService(
        now: () => now,
        available: () async => true,
        request: () async {
          requests++;
        },
      );
      await service.addReadingTime(const Duration(minutes: 1));
      await service.maybeRequest(canShow: () => true);
      expect(requests, 1);
    },
  );
  test('concurrent attempts, cooldown boundary and clock rollback', () async {
    await service.addReadingTime(const Duration(hours: 5));
    await Future.wait(
      List.generate(3, (_) => service.maybeRequest(canShow: () => true)),
    );
    expect(requests, 1);
    now = now.subtract(const Duration(days: 1));
    await service.maybeRequest(canShow: () => true);
    expect(requests, 1);
    now = now.add(const Duration(days: 90));
    await service.maybeRequest(canShow: () => true);
    expect(requests, 1);
    now = now.add(const Duration(days: 1));
    await service.maybeRequest(canShow: () => true);
    expect(requests, 2);
  });
  test(
    'navigation change during availability check defers without consuming eligibility',
    () async {
      await service.addReadingTime(const Duration(hours: 5));
      var visible = true;
      final other = ReaderReviewService(
        available: () async {
          visible = false;
          return true;
        },
        request: () async {
          requests++;
        },
      );
      await other.maybeRequest(canShow: () => visible);
      expect(requests, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString(ReaderReviewService.storageKey)!,
        )['lastRequestMs'],
        isNull,
      );
      await service.maybeRequest(canShow: () => true);
      expect(requests, 1);
    },
  );
  test(
    'unsupported store and plugin errors do not interrupt reading',
    () async {
      await service.addReadingTime(const Duration(hours: 5));
      final unavailable = ReaderReviewService(
        available: () async => false,
        request: () async {
          requests++;
        },
      );
      await unavailable.maybeRequest(canShow: () => true);
      expect(requests, 0);
      final failing = ReaderReviewService(
        available: () async => true,
        request: () async {
          throw StateError('plugin');
        },
        openStore: () async {
          throw StateError('store');
        },
      );
      await failing.maybeRequest(canShow: () => true);
      expect(await failing.openStore(), false);
      await service.maybeRequest(canShow: () => true);
      expect(requests, 0); // A failed OS request still has a cooldown.
    },
  );
  test('manual store link works without accumulated time', () async {
    var opened = 0;
    final manual = ReaderReviewService(
      openStore: () async {
        opened++;
      },
    );
    expect(await manual.openStore(), true);
    expect(opened, 1);
    expect(
      (await SharedPreferences.getInstance()).getString(
        ReaderReviewService.storageKey,
      ),
      isNull,
    );
  });
}
