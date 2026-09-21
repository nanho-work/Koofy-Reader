import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

enum AdvertisingChoice { standard, personalized }

class PrivacyState {
  const PrivacyState({
    this.loaded = false,
    this.choice,
    this.changedAt,
    this.att = 'notDetermined',
    this.effectivePersonalized = false,
    this.configured = false,
    this.revision = 0,
    this.error,
  });
  final bool loaded, effectivePersonalized, configured;
  final AdvertisingChoice? choice;
  final DateTime? changedAt;
  final String att;
  final int revision;
  final String? error;
  bool get canRequestAds => choice != null && configured;
}

abstract class PrivacyPlatform {
  bool get isIOS;
  Future<String> trackingStatus({bool request = false});
  Future<void> configure(bool personalized);
}

class DevicePrivacyPlatform implements PrivacyPlatform {
  static const channel = MethodChannel('com.koofylab.koofyreader/privacy');
  @override
  bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  @override
  Future<String> trackingStatus({bool request = false}) async {
    if (!isIOS) return 'notApplicable';
    var status = await ATTrackingManager.getTrackingAuthorizationStatus();
    if (request && status == ATTStatus.NotDetermined) {
      status = await ATTrackingManager.requestTrackingAuthorization();
    }
    return switch (status) {
      ATTStatus.Authorized => 'authorized',
      ATTStatus.Denied => 'denied',
      ATTStatus.Restricted => 'restricted',
      _ => 'notDetermined',
    };
  }

  @override
  Future<void> configure(bool personalized) async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && !isIOS)) {
      return;
    }
    await channel.invokeMethod<void>('configure', {
      'personalized': personalized,
    });
  }
}

/// Choices are local and versioned. All SDK entry points must call prepareAds;
/// merely acknowledging the policy must never be interpreted as ad consent.
class PrivacyService extends ChangeNotifier {
  PrivacyService({LocalStorage? storage, PrivacyPlatform? platform})
    : _storage = storage ?? SharedPrefsLocalStorage(),
      _platform = platform ?? DevicePrivacyPlatform();
  static final instance = PrivacyService();
  static const policyVersion = '2026-09-21';
  static const storageKey = 'reader_privacy_choice_v1';
  final LocalStorage _storage;
  final PrivacyPlatform _platform;
  PrivacyState state = const PrivacyState();
  Future<void> _queue = Future.value();
  bool get isIOS => _platform.isIOS;

  Future<void> _serialize(Future<void> Function() work) {
    final task = _queue.then((_) => work());
    _queue = task.catchError((Object _) {});
    return task;
  }

  void _emit(PrivacyState next) {
    state = next;
    notifyListeners();
  }

  Future<void> load() => _serialize(() async {
    if (state.loaded) return;
    try {
      final raw = await _storage.getString(storageKey);
      AdvertisingChoice? choice;
      DateTime? date;
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is Map && value['version'] == policyVersion) {
          choice = switch (value['choice']) {
            'standard' => AdvertisingChoice.standard,
            'personalized' => AdvertisingChoice.personalized,
            _ => null,
          };
          date = DateTime.tryParse(value['at']?.toString() ?? '');
          if (date == null) choice = null;
        }
      }
      _emit(PrivacyState(loaded: true, choice: choice, changedAt: date));
    } catch (_) {
      // A damaged/missing record never grants consent. Choosing again repairs it.
      _emit(
        const PrivacyState(
          loaded: true,
          error: '저장된 광고 선택을 확인하지 못했습니다. 다시 선택해 주세요.',
        ),
      );
    }
  });

  Future<void> choose(AdvertisingChoice choice) async {
    await load();
    await _serialize(() async {
      final date = DateTime.now().toUtc();
      await _storage.setString(
        storageKey,
        jsonEncode({
          'version': policyVersion,
          'choice': choice.name,
          'at': date.toIso8601String(),
        }),
      );
      // Remove old ad views before changing consent, even if native setup fails.
      _emit(
        PrivacyState(
          loaded: true,
          choice: choice,
          changedAt: date,
          revision: state.revision + 1,
        ),
      );
      await _configure(
        requestTracking: isIOS && choice == AdvertisingChoice.personalized,
      );
    });
  }

  Future<void> refresh() async {
    await load();
    await _serialize(() => _configure());
  }

  Future<bool> prepareAds() async {
    await refresh();
    return state.canRequestAds;
  }

  Future<void> _configure({bool requestTracking = false}) async {
    final choice = state.choice;
    if (choice == null) return;
    try {
      final att = await _platform.trackingStatus(request: requestTracking);
      final personal =
          choice == AdvertisingChoice.personalized &&
          (!_platform.isIOS || att == 'authorized');
      await _platform.configure(personal);
      final changed =
          state.effectivePersonalized != personal || state.att != att;
      _emit(
        PrivacyState(
          loaded: true,
          choice: choice,
          changedAt: state.changedAt,
          att: att,
          effectivePersonalized: personal,
          configured: true,
          revision: state.revision + (changed ? 1 : 0),
        ),
      );
    } catch (_) {
      _emit(
        PrivacyState(
          loaded: true,
          choice: choice,
          changedAt: state.changedAt,
          revision: state.revision + 1,
          error: '광고 개인정보 설정을 적용하지 못해 광고 요청을 중단했습니다. 독서는 계속할 수 있습니다.',
        ),
      );
    }
  }
}

final privacyServiceProvider = Provider<PrivacyService>(
  (ref) => PrivacyService.instance,
);
final privacyStateProvider = StreamProvider<PrivacyState>((ref) {
  final service = ref.watch(privacyServiceProvider);
  final stream = StreamController<PrivacyState>();
  void update() {
    if (!stream.isClosed) stream.add(service.state);
  }

  service.addListener(update);
  ref.onDispose(() {
    service.removeListener(update);
    unawaited(stream.close());
  });
  update();
  unawaited(service.refresh());
  return stream.stream;
});
