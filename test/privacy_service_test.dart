import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/privacy/data/privacy_service.dart';

class MemoryPrivacyStorage implements LocalStorage {
  final data = <String, String>{};
  bool fail = false;
  @override
  Future<void> remove(String key) async {
    data.remove(key);
  }

  @override
  Future<String?> getString(String key) async => data[key];
  @override
  Future<void> setString(String key, String value) async {
    if (fail) throw StateError('disk full');
    data[key] = value;
  }

  @override
  Future<int?> getInt(String key) async => int.tryParse(data[key] ?? '');
  @override
  Future<void> setInt(String key, int value) => setString(key, '$value');
  @override
  Future<Map<String, String>> getStringEntriesByPrefix(String prefix) async =>
      {};
}

class FakePrivacyPlatform implements PrivacyPlatform {
  FakePrivacyPlatform({this.isIOS = true});
  @override
  final bool isIOS;
  String status = 'notDetermined';
  String requestResult = 'denied';
  int requests = 0;
  bool fail = false;
  final configured = <bool>[];
  @override
  Future<String> trackingStatus({bool request = false}) async {
    if (request && status == 'notDetermined') {
      requests++;
      status = requestResult;
    }
    return status;
  }

  @override
  Future<void> configure(bool personalized) async {
    if (fail) throw StateError('native failure');
    configured.add(personalized);
  }
}

void main() {
  late MemoryPrivacyStorage storage;
  late FakePrivacyPlatform platform;
  late PrivacyService service;
  setUp(() {
    storage = MemoryPrivacyStorage();
    platform = FakePrivacyPlatform();
    service = PrivacyService(storage: storage, platform: platform);
  });
  tearDown(() => service.dispose());
  test('no SDK privacy or tracking calls before an explicit choice', () async {
    expect(await service.prepareAds(), false);
    expect(platform.configured, isEmpty);
    expect(platform.requests, 0);
  });
  test(
    'standard allows ads with restrictive signals, without asking ATT',
    () async {
      await service.choose(AdvertisingChoice.standard);
      expect(service.state.canRequestAds, true);
      expect(platform.configured, [false]);
      expect(platform.requests, 0);
      final saved = jsonDecode(storage.data[PrivacyService.storageKey]!);
      expect(saved['version'], PrivacyService.policyVersion);
      expect(saved['choice'], 'standard');
      expect(saved['at'], isNotEmpty);
    },
  );
  test(
    'ATT denial overrides personalization and does not block reading or ads',
    () async {
      await service.choose(AdvertisingChoice.personalized);
      expect(platform.requests, 1);
      expect(service.state.choice, AdvertisingChoice.personalized);
      expect(service.state.effectivePersonalized, false);
      expect(service.state.canRequestAds, true);
      await service.refresh();
      expect(platform.requests, 1);
      expect(platform.configured.every((v) => !v), true);
    },
  );
  test(
    'authorized ATT still requires in-app consent; revoke takes effect',
    () async {
      platform.status = 'authorized';
      await service.choose(AdvertisingChoice.standard);
      expect(platform.configured.last, false);
      await service.choose(AdvertisingChoice.personalized);
      expect(platform.configured.last, true);
      final revision = service.state.revision;
      platform.status = 'denied';
      await service.refresh();
      expect(platform.configured.last, false);
      expect(service.state.revision, greaterThan(revision));
    },
  );
  test('Android uses in-app choice without ATT', () async {
    final android = FakePrivacyPlatform(isIOS: false);
    final other = PrivacyService(storage: storage, platform: android);
    await other.choose(AdvertisingChoice.personalized);
    expect(other.state.effectivePersonalized, true);
    expect(android.requests, 0);
    other.dispose();
  });
  test('stored choice restores without a repeated tracking prompt', () async {
    platform.requestResult = 'authorized';
    await service.choose(AdvertisingChoice.personalized);
    final other = PrivacyService(storage: storage, platform: platform);
    expect(await other.prepareAds(), true);
    expect(platform.requests, 1);
    expect(other.state.effectivePersonalized, true);
    other.dispose();
  });
  test('failed persistence never starts ads', () async {
    storage.fail = true;
    await expectLater(
      service.choose(AdvertisingChoice.standard),
      throwsStateError,
    );
    expect(platform.configured, isEmpty);
    expect(service.state.canRequestAds, false);
  });
  test('failed native privacy configuration blocks all ad requests', () async {
    platform.fail = true;
    await service.choose(AdvertisingChoice.standard);
    expect(service.state.choice, AdvertisingChoice.standard);
    expect(service.state.canRequestAds, false);
    expect(await service.prepareAds(), false);
    platform.fail = false;
    expect(await service.prepareAds(), true);
  });
  test('corrupt or outdated records never imply consent', () async {
    for (final raw in [
      'broken',
      '{"version":"old","choice":"personalized","at":"2026-09-21"}',
    ]) {
      storage.data[PrivacyService.storageKey] = raw;
      final other = PrivacyService(storage: storage, platform: platform);
      expect(await other.prepareAds(), false);
      expect(platform.configured, isEmpty);
      other.dispose();
    }
  });
}
