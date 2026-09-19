import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_coordinator.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader_bridge/koofy_reader_bridge.dart';
import 'package:path_provider/path_provider.dart';

class NativeReaderServices {
  const NativeReaderServices({
    required this.preparer,
    required this.coordinator,
    this.supportDirectory,
  });
  final Directory? supportDirectory;
  final ReadingPublicationPreparer preparer;
  final NativeReaderCoordinator coordinator;
}

// App-scoped, not tied to whether the Flutter launch screen is visible.
final nativeReaderServicesProvider = FutureProvider<NativeReaderServices>((
  ref,
) async {
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/native_reader_v1');
  await directory.create(recursive: true);
  final coordinator = NativeReaderCoordinator(
    gateway: NativeReaderGateway(),
    store: NativeReaderStore.open(File('${directory.path}/reader.sqlite')),
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return NativeReaderServices(
    coordinator: coordinator,
    supportDirectory: support,
    preparer: ReadingPublicationPreparer(
      storageDirectory: Directory('${directory.path}/publications'),
    ),
  );
});
