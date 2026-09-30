import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';

const readerCoverSettingKey = 'reader_show_registered_cover_v1';
final readerCoverEnabledProvider = FutureProvider<bool>(
  (ref) async =>
      await ref.watch(localStorageProvider).getInt(readerCoverSettingKey) != 0,
);
