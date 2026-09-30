import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AdConsentResult {
  const AdConsentResult({
    required this.canRequestAds,
    this.privacyOptionsRequired = false,
    this.permitsPersonalization = false,
  });
  final bool canRequestAds;
  final bool privacyOptionsRequired;
  // UMP "obtained" includes refusals. It is never a personalization grant.
  final bool permitsPersonalization;
}

abstract class AdConsentPlatform {
  Future<AdConsentResult> prepare();
  Future<AdConsentResult> showOptions();
}

class DeviceAdConsentPlatform implements AdConsentPlatform {
  static const _channel = MethodChannel('com.koofylab.koofyreader/privacy');

  Future<AdConsentResult> _call(String method) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const AdConsentResult(canRequestAds: false);
    }
    final map = await _channel.invokeMapMethod<String, dynamic>(method);
    return AdConsentResult(
      canRequestAds: map?['canRequestAds'] == true,
      privacyOptionsRequired: map?['privacyOptionsRequired'] == true,
      permitsPersonalization: map?['permitsPersonalization'] == true,
    );
  }

  @override
  Future<AdConsentResult> prepare() => _call('prepareConsent');
  @override
  Future<AdConsentResult> showOptions() => _call('showConsentOptions');
}
