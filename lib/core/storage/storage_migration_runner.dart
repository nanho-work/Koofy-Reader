import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';

/// The retired reader's keys are no longer rewritten at application startup.
/// Snapshot them verbatim before the Readium-only app can open any publication.
class StorageMigrationRunner {
  StorageMigrationRunner({LocalStorage? storage})
    : _archive = LegacyReaderArchive(storage ?? SharedPrefsLocalStorage());
  final LegacyReaderArchive _archive;
  Future<void> run() async {
    await _archive.backup();
  }
}
