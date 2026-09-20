import 'package:flutter/foundation.dart';

class LevelPlayIds {
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get _android => defaultTargetPlatform == TargetPlatform.android;
  static String get appKey => _android ? '283bb581d' : '283bb91a5';
  static String get libraryBanner =>
      _android ? 'rd7fp4ib5ob9wxqa' : 'ylwd5e3aw6xjman2';
  static String get readerBanner =>
      _android ? '2dr1bupao7hqz66b' : 'f60hdb7l3a4o9fgt';
  static String get rewarded =>
      _android ? 'c3al5bjpm4gizhi5' : 'jppve7gfp2mtrm44';
  // Diagnostic suite is opt-in and never enabled in release builds.
  // This does NOT force test inventory; register the device in LevelPlay.
  static const bool testSuite =
      !kReleaseMode && bool.fromEnvironment('LEVELPLAY_TEST_SUITE');
}
