import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:koofy_reader/core/theme/app_appearance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:koofy_reader/app/app.dart';
import 'package:koofy_reader/app/bootstrap.dart';
import 'package:koofy_reader/firebase_options.dart';
import 'package:koofy_reader/core/storage/storage_migration_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['NanumGothic', 'NanumMyeongjo']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/$font-OFL.txt'));
    }
  });
  runApp(
    ReaderBootstrap(
      initialize: _initialize,
      child: const ProviderScope(child: KoofyReaderApp()),
    ),
  );
}

Future<void> _initialize() async {
  await AppLanguage.instance.initialize();
  await AppAppearance.instance.initialize();
  await StorageMigrationRunner().run();
  final mobile =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (mobile) {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: ReaderFirebaseOptions.currentPlatform,
      );
    }
  }
  await ReaderAnalytics.instance.initialize(mobile: mobile);
}
