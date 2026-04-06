import 'package:flutter/foundation.dart';

class AdMobIds {
  // Default true for safety: development builds use test IDs unless explicitly disabled.
  static const bool useTestIds = bool.fromEnvironment(
    'USE_ADMOB_TEST_IDS',
    defaultValue: true,
  );

  static const String _androidBannerProd = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: '',
  );

  static const String _androidRewardedProd = String.fromEnvironment(
    'ADMOB_REWARDED_ANDROID',
    defaultValue: '',
  );

  static const String _iosBannerProd = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: '',
  );

  static const String _iosRewardedProd = String.fromEnvironment(
    'ADMOB_REWARDED_IOS',
    defaultValue: '',
  );

  // Official Google Mobile Ads test unit IDs.
  static const String _androidBannerTest =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _androidRewardedTest =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _iosBannerTest = 'ca-app-pub-3940256099942544/2934735716';
  static const String _iosRewardedTest =
      'ca-app-pub-3940256099942544/1712485313';

  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static String? get bannerUnitId {
    if (!isSupportedPlatform) return null;
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (useTestIds) return _androidBannerTest;
      return _androidBannerProd.isNotEmpty ? _androidBannerProd : null;
    }
    if (useTestIds) return _iosBannerTest;
    return _iosBannerProd.isNotEmpty ? _iosBannerProd : null;
  }

  static String? get rewardedUnitId {
    if (!isSupportedPlatform) return null;
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (useTestIds) return _androidRewardedTest;
      return _androidRewardedProd.isNotEmpty ? _androidRewardedProd : null;
    }
    if (useTestIds) return _iosRewardedTest;
    return _iosRewardedProd.isNotEmpty ? _iosRewardedProd : null;
  }
}
