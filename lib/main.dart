import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:koofy_reader/app/app.dart';
import 'package:koofy_reader/firebase_options.dart';
import 'package:koofy_reader/features/ads/data/levelplay_service.dart';
import 'package:koofy_reader/core/storage/storage_migration_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageMigrationRunner().run();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await Firebase.initializeApp(
      options: ReaderFirebaseOptions.currentPlatform,
    );
  }
  unawaited(LevelPlayService.instance.initialize());
  runApp(const ProviderScope(child: KoofyReaderApp()));
}
