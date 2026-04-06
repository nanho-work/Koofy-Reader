import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/ads/domain/ad_state.dart';

final adRepositoryProvider = Provider<AdRepository>(
  (ref) => LocalAdRepository(ref.watch(localStorageProvider)),
);

final adStateProvider = FutureProvider<AdState>(
  (ref) => ref.watch(adRepositoryProvider).getState(),
);

abstract class AdRepository {
  Future<AdState> getState();
  Future<void> hideBannerForHours(int hours);
}

class LocalAdRepository implements AdRepository {
  LocalAdRepository(this._storage);

  final LocalStorage _storage;

  @override
  Future<AdState> getState() async {
    final expiryEpochMs = await _storage.getInt(AppConstants.adHideExpiryKey);
    if (expiryEpochMs == null) {
      return const AdState(hiddenUntil: null);
    }
    return AdState(
      hiddenUntil: DateTime.fromMillisecondsSinceEpoch(expiryEpochMs),
    );
  }

  @override
  Future<void> hideBannerForHours(int hours) async {
    final expiry = DateTime.now().add(Duration(hours: hours));
    await _storage.setInt(
      AppConstants.adHideExpiryKey,
      expiry.millisecondsSinceEpoch,
    );
  }
}
