import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:koofy_reader/app/app.dart';
import 'package:koofy_reader/features/ads/config/admob_ids.dart';
import 'package:koofy_reader/core/storage/storage_migration_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageMigrationRunner().run();
  if (!kIsWeb && AdMobIds.isSupportedPlatform) {
    await MobileAds.instance.initialize();
  }
  runApp(const ProviderScope(child: KoofyReaderApp()));
}
