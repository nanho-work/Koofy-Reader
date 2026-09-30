import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'ad_consent.dart';

enum AdvertisingChoice {
  standard,
  personalized,
  // A completed iOS notice, NOT a grant of tracking permission.
  systemTracking,
}

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
    this.privacyOptionsRequired = false,
  });
  final bool loaded, effectivePersonalized, configured;
  final AdvertisingChoice? choice;
  final DateTime? changedAt;
  final String att;
  final int revision;
  final String? error;
  final bool privacyOptionsRequired;
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
  PrivacyService({
    LocalStorage? storage,
    PrivacyPlatform? platform,
    AdConsentPlatform? consent,
  }) : _storage = storage ?? SharedPrefsLocalStorage(),
       _platform = platform ?? DevicePrivacyPlatform(),
       _consent = consent ?? DeviceAdConsentPlatform();
  static final instance = PrivacyService();
  static const policyVersion = '2026-09-21';
  static const documentUpdatedAt = '2026-09-29';
  static const storageKey = 'reader_privacy_choice_v1';
  final LocalStorage _storage;
  final PrivacyPlatform _platform;
  final AdConsentPlatform _consent;
  AdConsentResult? _consentResult;
  Future<void>? _optionsTask;
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
            'systemTracking' =>
              isIOS
                  ? AdvertisingChoice.systemTracking
                  : AdvertisingChoice.standard,
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
      await _saveChoice(choice);
      // Settings never use an app-level choice as an ATT pre-prompt.
      await _configure();
    });
  }

  Future<void> continueIOSTrackingNotice() async {
    if (!isIOS) throw StateError('The tracking notice is iOS-only');
    await load();
    await _serialize(() async {
      // Preserve existing choices, including older explicit refusals. Also
      // protects against double taps queued while the system prompt is open.
      if (state.choice != null) return;
      try {
        await _platform.trackingStatus(request: true);
      } catch (_) {
        // An unavailable prompt must never grant permission or block reading.
        await _saveChoice(AdvertisingChoice.standard);
        await _configure();
        return;
      }
      await _saveChoice(AdvertisingChoice.systemTracking);
      // Re-read the OS result; Continue itself is not consent. No SDK setup or
      // completed notice is published while the system prompt is pending.
      await _configure();
    });
  }

  Future<void> _saveChoice(AdvertisingChoice choice) async {
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
  }

  Future<void> refresh() async {
    await load();
    await _serialize(() => _configure());
  }

  Future<bool> prepareAds() async {
    await refresh();
    return state.canRequestAds;
  }

  Future<void> retryConsent() => _serialize(() async {
    _consentResult = null;
    await _configure();
  });

  Future<void> showConsentOptions() {
    if (_optionsTask != null) return _optionsTask!;
    final task = _showConsentOptions();
    _optionsTask = task;
    return task.whenComplete(() => _optionsTask = null);
  }

  Future<void> _showConsentOptions() => _serialize(() async {
    final previous = state;
    // Dispose ad views while choices can change; stale loaded ads must not survive.
    _emit(
      PrivacyState(
        loaded: true,
        choice: previous.choice,
        changedAt: previous.changedAt,
        att: previous.att,
        revision: previous.revision + 1,
        privacyOptionsRequired: previous.privacyOptionsRequired,
      ),
    );
    try {
      _consentResult = await _consent.showOptions();
    } catch (_) {
      _consentResult = const AdConsentResult(
        canRequestAds: false,
        privacyOptionsRequired: true,
      );
    }
    await _configure();
  });

  Future<void> _configure() async {
    final choice = state.choice;
    if (choice == null) return;
    try {
      // Once per cold start. Do not present a new form on every banner request
      // or app resume. Explicit retry is available after a network failure.
      if (_consentResult == null) {
        try {
          _consentResult = await _consent.prepare();
        } catch (_) {
          _consentResult = const AdConsentResult(canRequestAds: false);
        }
      }
      final consent = _consentResult!;
      final att = await _platform.trackingStatus();
      final personal =
          (choice == AdvertisingChoice.personalized ||
              (isIOS && choice == AdvertisingChoice.systemTracking)) &&
          (!isIOS || att == 'authorized') &&
          consent.canRequestAds &&
          consent.permitsPersonalization;
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
          configured: consent.canRequestAds,
          privacyOptionsRequired: consent.privacyOptionsRequired,
          error: consent.canRequestAds
              ? null
              : '광고 개인정보 확인을 완료하지 못해 광고를 잠시 중단했습니다. 독서는 계속할 수 있습니다.',
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
          privacyOptionsRequired:
              _consentResult?.privacyOptionsRequired ?? false,
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
