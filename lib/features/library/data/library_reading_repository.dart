import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/domain/library_reading_state.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reading_progress.dart';

final nativeReaderAvailableProvider = Provider<bool>(
  (ref) =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS),
);

final nativeLibraryPositionsProvider =
    FutureProvider<List<NativeLibraryPosition>>((ref) async {
      if (!ref.watch(nativeReaderAvailableProvider)) return const [];
      final services = await ref.watch(nativeReaderServicesProvider.future);
      await services.coordinator.flush();
      return services.coordinator.store.loadLibraryPositions();
    });

final libraryCompletionRepositoryProvider = Provider(
  (ref) => LibraryCompletionRepository(ref.watch(localStorageProvider)),
);

final libraryCompletionProvider = FutureProvider<Map<String, bool>>(
  (ref) => ref.watch(libraryCompletionRepositoryProvider).load(),
);

final libraryReadingStateProvider =
    FutureProvider<Map<String, LibraryReadingState>>((ref) async {
      final legacy = ref.watch(legacyReadingProgressProvider.future);
      final native = ref.watch(nativeLibraryPositionsProvider.future);
      final completion = ref.watch(libraryCompletionProvider.future);
      // Register all dependencies before awaiting; await all errors as well.
      final values = await Future.wait<Object>([legacy, native, completion]);
      return mergeLibraryReadingStates(
        legacy: values[0] as Map<String, ReadingProgress>,
        native: values[1] as List<NativeLibraryPosition>,
        completion: values[2] as Map<String, bool>,
      );
    });

class LibraryCompletionRepository {
  LibraryCompletionRepository(this.storage);
  final LocalStorage storage;
  static const prefix = 'library_completion_v1:';

  Future<Map<String, bool>> load() async => {
    for (final entry in (await storage.getStringEntriesByPrefix(
      prefix,
    )).entries)
      if (entry.value == 'true' || entry.value == 'false')
        entry.key.substring(prefix.length): entry.value == 'true',
  };

  Future<void> setFinished(String bookId, bool finished) =>
      storage.setString('$prefix$bookId', '$finished');
}
