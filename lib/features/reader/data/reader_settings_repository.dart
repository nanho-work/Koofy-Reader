import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';

final readerSettingsRepositoryProvider = Provider<ReaderSettingsRepository>(
  (ref) => LocalReaderSettingsRepository(ref.watch(localStorageProvider)),
);

abstract class ReaderSettingsRepository {
  Future<ReaderSettings> load();
  Future<void> save(ReaderSettings settings);
}

class LocalReaderSettingsRepository implements ReaderSettingsRepository {
  LocalReaderSettingsRepository(this._storage);

  final LocalStorage _storage;

  @override
  Future<ReaderSettings> load() async {
    final raw = await _storage.getString(AppConstants.readerSettingsKey);
    if (raw == null) {
      return ReaderSettings.defaults();
    }
    return ReaderSettings.fromRaw(raw) ?? ReaderSettings.defaults();
  }

  @override
  Future<void> save(ReaderSettings settings) async {
    await _storage.setString(AppConstants.readerSettingsKey, settings.toRaw());
  }
}
