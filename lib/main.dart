import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:koofy_reader/app/app.dart';
import 'package:koofy_reader/app/bootstrap.dart';
import 'package:koofy_reader/firebase_options.dart';
import 'package:koofy_reader/core/storage/storage_migration_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ReaderBootstrap(
      initialize: _initialize,
      child: const ProviderScope(child: KoofyReaderApp()),
    ),
  );
}

Future<void> _initialize() async {
  await StorageMigrationRunner().run();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: ReaderFirebaseOptions.currentPlatform,
      );
    }
  }
}
