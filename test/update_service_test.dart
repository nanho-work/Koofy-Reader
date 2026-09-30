import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/updates/data/update_service.dart';
import 'package:koofy_reader/features/updates/domain/update_policy.dart';
import 'update_policy_test.dart' show updateValues;

class FakeUpdateSource implements UpdateSource {
  FakeUpdateSource(this.values);
  final Map<String, String> values;
  int calls = 0;
  bool fail = false;
  Completer<Map<String, String>>? pending;
  @override
  Future<Map<String, String>> fetch() async {
    calls++;
    if (fail) throw StateError('offline');
    return pending == null ? values : await pending!.future;
  }
}

void main() {
  test(
    'cold start check is shared, dismissal survives remount but not a new session',
    () async {
      final source = FakeUpdateSource(updateValues());
      UpdateService create() => UpdateService(
        source: source,
        platform: UpdatePlatform.android,
        installedVersion: () async => '1.0.0',
      );
      final service = create();
      await Future.wait([
        service.checkOnColdStart(),
        service.checkOnColdStart(),
      ]);
      service.dismissForSession();
      await service.checkOnColdStart();
      expect(source.calls, 1);
      expect(service.dismissed, true);
      final restarted = create();
      expect(await restarted.checkOnColdStart(), isNotNull);
      expect(restarted.dismissed, false);
      expect(source.calls, 2);
    },
  );
  test('offline and version lookup failures allow reading', () async {
    final source = FakeUpdateSource(updateValues())..fail = true;
    final service = UpdateService(
      source: source,
      platform: UpdatePlatform.android,
      installedVersion: () async => '1.0.0',
    );
    expect(await service.checkOnColdStart(), isNull);
    final broken = UpdateService(
      source: source,
      platform: UpdatePlatform.ios,
      installedVersion: () async => throw StateError('no plugin'),
    );
    expect(await broken.checkOnColdStart(), isNull);
  });
  test('timeout ignores late config for the entire session', () async {
    final source = FakeUpdateSource(updateValues())..pending = Completer();
    final service = UpdateService(
      source: source,
      platform: UpdatePlatform.android,
      installedVersion: () async => '1.0.0',
      timeout: const Duration(milliseconds: 10),
    );
    expect(await service.checkOnColdStart(), isNull);
    source.pending!.complete(updateValues(minimum: '1.2.0'));
    expect(await service.checkOnColdStart(), isNull);
    expect(source.calls, 1);
  });
  test('test distributions and unsupported platforms never fetch', () async {
    final source = FakeUpdateSource(updateValues());
    for (final platform in [null, UpdatePlatform.ios]) {
      final service = UpdateService(
        source: source,
        platform: platform,
        installedVersion: () async => '1.0.0',
        channel: 'testing',
      );
      expect(await service.checkOnColdStart(), isNull);
    }
    expect(source.calls, 0);
  });
  test('committed Firebase template is disabled and matches the app schema', () {
    final template =
        jsonDecode(File('remoteconfig.template.json').readAsStringSync())
            as Map;
    for (final platform in UpdatePlatform.values) {
      final params =
          template['parameterGroups']['${platform.name}_updates']['parameters']
              as Map;
      final values = params.map(
        (key, value) =>
            MapEntry(key as String, value['defaultValue']['value'] as String),
      );
      expect(values['${platform.name}_update_enabled'], 'false');
      // Enabling the template in a test must yield a valid mandatory rule.
      values['${platform.name}_update_enabled'] = 'true';
      final notice = UpdateNotice.evaluate(values, platform, '0.9.0');
      expect(notice, isNotNull);
      expect(notice!.required, true);
    }
  });
}
