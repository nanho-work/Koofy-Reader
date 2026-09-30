import 'dart:async';
import 'dart:convert';
import 'package:koofy_reader/features/privacy/data/ad_consent.dart';
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
  Completer<String>? pendingRequest;
  bool failTracking = false;
  @override
  Future<String> trackingStatus({bool request = false}) async {
    if (request && status == 'notDetermined') {
      requests++;
      if (failTracking) throw StateError('ATT unavailable');
      status = pendingRequest == null
          ? requestResult
          : await pendingRequest!.future;
    }
    return status;
  }

  @override
  Future<void> configure(bool personalized) async {
    if (fail) throw StateError('native failure');
    configured.add(personalized);
  }
}

class FakeAdConsent extends AdConsentPlatform {
  AdConsentResult result = const AdConsentResult(
    canRequestAds: true,
    permitsPersonalization: true,
  );
  int prepares = 0;
  int options = 0;
  bool failPrepare = false;
  Completer<AdConsentResult>? pending;
  @override
  Future<AdConsentResult> prepare() async {
    prepares++;
    if (failPrepare) throw StateError("network unavailable");
    return pending == null ? result : await pending!.future;
  }

  @override
  Future<AdConsentResult> showOptions() async {
    options++;
    return pending == null ? result : await pending!.future;
  }
}

void main() {
  late MemoryPrivacyStorage storage;
  late FakePrivacyPlatform platform;
  late PrivacyService service;
  setUp(() {
    storage = MemoryPrivacyStorage();
    platform = FakePrivacyPlatform();
    service = PrivacyService(
      consent: FakeAdConsent(),
      storage: storage,
      platform: platform,
    );
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
      await service.continueIOSTrackingNotice();
      expect(platform.requests, 1);
      expect(service.state.choice, AdvertisingChoice.systemTracking);
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
    final other = PrivacyService(
      consent: FakeAdConsent(),
      storage: storage,
      platform: android,
    );
    await other.choose(AdvertisingChoice.personalized);
    expect(other.state.effectivePersonalized, true);
    expect(android.requests, 0);
    other.dispose();
  });
  test('stored choice restores without a repeated tracking prompt', () async {
    platform.requestResult = 'authorized';
    await service.continueIOSTrackingNotice();
    final other = PrivacyService(
      consent: FakeAdConsent(),
      storage: storage,
      platform: platform,
    );
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
      final other = PrivacyService(
        consent: FakeAdConsent(),
        storage: storage,
        platform: platform,
      );
      expect(await other.prepareAds(), false);
      expect(platform.configured, isEmpty);
      other.dispose();
    }
  });

  test(
    'Continue awaits ATT; no saved grant or ad setup while pending',
    () async {
      platform.pendingRequest = Completer<String>();
      final task = service.continueIOSTrackingNotice();
      await Future<void>.delayed(Duration.zero);
      expect(platform.requests, 1);
      expect(service.state.choice, isNull);
      expect(storage.data, isEmpty);
      expect(platform.configured, isEmpty);
      platform.pendingRequest!.complete('authorized');
      await task;
      expect(service.state.effectivePersonalized, true);
      expect(
        jsonDecode(storage.data[PrivacyService.storageKey]!)['choice'],
        'systemTracking',
      );
    },
  );

  for (final status in ['denied', 'restricted', 'notDetermined']) {
    test(
      'ATT $status never enables personalization on Continue or restart',
      () async {
        platform.status = status;
        platform.requestResult = status;
        await service.continueIOSTrackingNotice();
        final requests = platform.requests;
        final other = PrivacyService(
          consent: FakeAdConsent(),
          storage: storage,
          platform: platform,
        );
        expect(await other.prepareAds(), true);
        expect(other.state.effectivePersonalized, false);
        expect(platform.configured.every((v) => !v), true);
        expect(platform.requests, requests);
        other.dispose();
      },
    );
  }

  test(
    'legacy refusal survives upgrade even when OS tracking is authorized',
    () async {
      storage.data[PrivacyService.storageKey] = jsonEncode({
        'version': '2026-09-21',
        'choice': 'standard',
        'at': '2026-09-21',
      });
      final before = storage.data[PrivacyService.storageKey];
      platform.status = 'authorized';
      await service.refresh();
      await service.continueIOSTrackingNotice();
      expect(service.state.choice, AdvertisingChoice.standard);
      expect(service.state.effectivePersonalized, false);
      expect(platform.requests, 0);
      expect(storage.data[PrivacyService.storageKey], before);
    },
  );

  test('double Continue and lifecycle refresh do not repeat ATT', () async {
    await Future.wait([
      service.continueIOSTrackingNotice(),
      service.continueIOSTrackingNotice(),
      service.refresh(),
    ]);
    expect(platform.requests, 1);
    expect(service.state.canRequestAds, true);
  });

  test(
    'new flow honors OS revocation and app restriction without prompting',
    () async {
      platform.requestResult = 'authorized';
      await service.continueIOSTrackingNotice();
      await service.choose(AdvertisingChoice.standard);
      expect(service.state.effectivePersonalized, false);
      await service.choose(AdvertisingChoice.systemTracking);
      expect(service.state.effectivePersonalized, true);
      platform.status = 'denied';
      await service.refresh();
      expect(service.state.effectivePersonalized, false);
      expect(platform.requests, 1);
    },
  );

  test(
    'ATT request failure permits reading using a restrictive preference',
    () async {
      platform.failTracking = true;
      await service.continueIOSTrackingNotice();
      expect(service.state.choice, AdvertisingChoice.standard);
      expect(service.state.canRequestAds, true);
      expect(service.state.effectivePersonalized, false);
      await service.refresh();
      expect(platform.requests, 1);
    },
  );

  test(
    'storage failure after ATT cannot initialize ads and retry is safe',
    () async {
      platform.requestResult = 'authorized';
      storage.fail = true;
      await expectLater(service.continueIOSTrackingNotice(), throwsStateError);
      expect(service.state.choice, isNull);
      expect(platform.configured, isEmpty);
      storage.fail = false;
      await service.continueIOSTrackingNotice();
      expect(platform.requests, 1);
      expect(service.state.effectivePersonalized, true);
    },
  );
  test(
    'UMP pending blocks ads and concurrent requests share one consent update',
    () async {
      final cmp = FakeAdConsent()..pending = Completer<AdConsentResult>();
      final reader = PrivacyService(
        storage: storage,
        platform: platform,
        consent: cmp,
      );
      final choosing = reader.choose(AdvertisingChoice.standard);
      await Future<void>.delayed(Duration.zero);
      expect(reader.state.canRequestAds, false);
      expect(
        reader.state.choice,
        AdvertisingChoice.standard,
      ); // Reading remains available.
      final requests = Future.wait([reader.prepareAds(), reader.prepareAds()]);
      cmp.pending!.complete(const AdConsentResult(canRequestAds: true));
      await choosing;
      expect(await requests, [true, true]);
      expect(cmp.prepares, 1);
      reader.dispose();
    },
  );
  test(
    'CMP refusal is not a personalization grant; options revocation blocks ads',
    () async {
      platform.status = 'authorized';
      final cmp = FakeAdConsent()
        ..result = const AdConsentResult(
          canRequestAds: true,
          privacyOptionsRequired: true,
        );
      final reader = PrivacyService(
        storage: storage,
        platform: platform,
        consent: cmp,
      );
      await reader.choose(AdvertisingChoice.personalized);
      expect(reader.state.canRequestAds, true);
      expect(reader.state.effectivePersonalized, false);
      expect(platform.configured.last, false);
      final revision = reader.state.revision;
      cmp.result = const AdConsentResult(
        canRequestAds: false,
        privacyOptionsRequired: true,
      );
      await reader.showConsentOptions();
      expect(reader.state.canRequestAds, false);
      expect(reader.state.privacyOptionsRequired, true);
      expect(reader.state.revision, greaterThan(revision));
      reader.dispose();
    },
  );
  test(
    'UMP unavailable permits reading; explicit retry can recover without ATT again',
    () async {
      final cmp = FakeAdConsent()
        ..result = const AdConsentResult(canRequestAds: false);
      final reader = PrivacyService(
        storage: storage,
        platform: platform,
        consent: cmp,
      );
      await reader.continueIOSTrackingNotice();
      expect(reader.state.choice, AdvertisingChoice.systemTracking);
      expect(reader.state.canRequestAds, false);
      cmp.result = const AdConsentResult(canRequestAds: true);
      await reader.retryConsent();
      expect(reader.state.canRequestAds, true);
      expect(platform.requests, 1);
      reader.dispose();
    },
  );
  test('native consent failure is cached until explicit retry', () async {
    final cmp = FakeAdConsent()..failPrepare = true;
    final reader = PrivacyService(
      storage: storage,
      platform: platform,
      consent: cmp,
    );
    await reader.choose(AdvertisingChoice.standard);
    await reader.prepareAds();
    await reader.refresh();
    expect(cmp.prepares, 1);
    expect(reader.state.canRequestAds, false);
    cmp.failPrepare = false;
    await reader.retryConsent();
    expect(reader.state.canRequestAds, true);
    expect(cmp.prepares, 2);
    reader.dispose();
  });
  test(
    'double options tap presents only once and immediately withdraws ad eligibility',
    () async {
      final cmp = FakeAdConsent();
      final reader = PrivacyService(
        storage: storage,
        platform: platform,
        consent: cmp,
      );
      await reader.choose(AdvertisingChoice.standard);
      cmp.pending = Completer<AdConsentResult>();
      final a = reader.showConsentOptions();
      final b = reader.showConsentOptions();
      await Future<void>.delayed(Duration.zero);
      expect(reader.state.canRequestAds, false);
      expect(cmp.options, 1);
      cmp.pending!.complete(const AdConsentResult(canRequestAds: true));
      await Future.wait([a, b]);
      expect(cmp.options, 1);
      reader.dispose();
    },
  );
}
