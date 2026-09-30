import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../domain/update_policy.dart';

abstract class UpdateSource {
  Future<Map<String, String>> fetch();
}

class FirebaseUpdateSource implements UpdateSource {
  @override
  Future<Map<String, String>> fetch() async {
    final remote = FirebaseRemoteConfig.instance;
    await remote.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 3),
        minimumFetchInterval: Duration.zero,
      ),
    );
    // Cold start only. Never consume a cached mandatory rule after a failed
    // network request. A throttle/error/timeout allows offline reading.
    await remote.fetchAndActivate();
    if (remote.lastFetchStatus != RemoteConfigFetchStatus.success) return {};
    return remote.getAll().map((key, value) => MapEntry(key, value.asString()));
  }
}

class UpdateService {
  UpdateService({
    required this.source,
    required this.platform,
    required this.installedVersion,
    this.channel = 'store',
    this.timeout = const Duration(seconds: 4),
  });
  final UpdateSource source;
  final UpdatePlatform? platform;
  final Future<String> Function() installedVersion;
  final String channel;
  final Duration timeout;
  Future<UpdateNotice?>? _startup;
  bool _dismissed = false;

  // One check per process/provider lifetime, independent of routes or resumes.
  Future<UpdateNotice?> checkOnColdStart() => _startup ??= _check();
  bool get dismissed => _dismissed;
  void dismissForSession() => _dismissed = true;

  Future<UpdateNotice?> _check() async {
    if (platform == null || channel != 'store') return null;
    try {
      return await (() async {
        final version = await installedVersion();
        final values = await source.fetch();
        return UpdateNotice.evaluate(values, platform!, version);
      })().timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}

final installedPackageProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
final updateServiceProvider = Provider<UpdateService>(
  (ref) => UpdateService(
    source: FirebaseUpdateSource(),
    platform: kIsWeb
        ? null
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => UpdatePlatform.android,
            TargetPlatform.iOS => UpdatePlatform.ios,
            _ => null,
          },
    installedVersion: () async =>
        (await ref.read(installedPackageProvider.future)).version,
    channel: const String.fromEnvironment(
      'READER_UPDATE_CHANNEL',
      defaultValue: 'store',
    ),
  ),
);
