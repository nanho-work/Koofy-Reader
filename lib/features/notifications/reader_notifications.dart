import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';

String notificationBase(CatalogItem item) {
  if (item.issueMonth.isNotEmpty) return 'monthly';
  final group = item.json['translationGroupId'];
  return 'work_${group is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(group) ? group : item.id}';
}

String notificationTopic(String base, String language) =>
    'reader_${base}_$language';
bool _validBase(String value) =>
    value == 'monthly' || RegExp(r'^work_[a-f0-9]{32}$').hasMatch(value);

enum ReaderNotificationPermission { unknown, allowed, denied }

// APNs registration completes asynchronously after auto-init is enabled.
// Never request an FCM subscription until Apple has returned the device token.
@visibleForTesting
Future<bool> waitForReaderApns(
  Future<bool> Function() ready, {
  Future<void> Function(Duration)? pause,
  int attempts = 21,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (await ready()) return true;
    if (attempt + 1 < attempts) {
      await (pause ?? Future<void>.delayed)(const Duration(milliseconds: 500));
    }
  }
  return false;
}

abstract class ReaderNotificationPlatform {
  bool get available;
  Future<ReaderNotificationPermission> permission({bool request = false});
  Future<void> autoInit(bool enabled);
  Future<void> subscribe(String topic);
  Future<void> unsubscribe(String topic);
  Future<bool> apnsReady();
  Future<void> openSettings();
}

class DeviceReaderNotifications implements ReaderNotificationPlatform {
  @override
  bool get available => !kIsWeb && Firebase.apps.isNotEmpty;
  @override
  Future<ReaderNotificationPermission> permission({
    bool request = false,
  }) async {
    final settings = request
        ? await FirebaseMessaging.instance.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
        : await FirebaseMessaging.instance.getNotificationSettings();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => ReaderNotificationPermission.allowed,
      AuthorizationStatus.denied => ReaderNotificationPermission.denied,
      _ => ReaderNotificationPermission.unknown,
    };
  }

  @override
  Future<void> autoInit(bool enabled) =>
      FirebaseMessaging.instance.setAutoInitEnabled(enabled);
  @override
  Future<void> subscribe(String topic) =>
      FirebaseMessaging.instance.subscribeToTopic(topic);
  @override
  Future<void> unsubscribe(String topic) =>
      FirebaseMessaging.instance.unsubscribeFromTopic(topic);
  @override
  Future<bool> apnsReady() async =>
      defaultTargetPlatform != TargetPlatform.iOS ||
      await waitForReaderApns(
        () async => await FirebaseMessaging.instance.getAPNSToken() != null,
      );
  @override
  Future<void> openSettings() => const MethodChannel(
    'com.koofylab.koofyreader/privacy',
  ).invokeMethod<void>('notificationSettings');
}

final readerNotificationsProvider = Provider<ReaderNotifications>(
  (ref) => ReaderNotifications.instance,
);
// The process-owned service outlives individual routes and ProviderScopes.
final readerNotificationsChangesProvider = StreamProvider<int>((ref) {
  final service = ref.watch(readerNotificationsProvider);
  final changes = StreamController<int>();
  var revision = 0;
  void changed() => changes.add(++revision);
  service.addListener(changed);
  ref.onDispose(() {
    service.removeListener(changed);
    unawaited(changes.close());
  });
  return changes.stream;
});
final notificationPreferencesProvider = FutureProvider<void>(
  (ref) => ref.watch(readerNotificationsProvider).initialize(),
);

/// Favorites are local, independent of OS permission and downloads. No startup prompt/token.
class ReaderNotifications extends ChangeNotifier with WidgetsBindingObserver {
  ReaderNotifications({ReaderNotificationPlatform? platform})
    : _platform = platform ?? DeviceReaderNotifications();
  static final instance = ReaderNotifications();
  static const preference = 'reader_notifications_v1';
  final ReaderNotificationPlatform _platform;
  final opens = StreamController<Map<String, String>>.broadcast();
  Map<String, String> _favorites = {};
  Map<String, String> get favorites => Map.unmodifiable(_favorites);
  Set<String> _actual = {};
  Future<void> _syncQueue = Future.value(), _changes = Future.value();
  Future<void>? _initialization;
  bool _initialized = false, _observing = false;
  bool _firstReadingStarted = false;
  bool enabled = true, asked = false, _favoriteNoticeShown = false;
  bool _firstReadingHandled = false;
  // An old explicit all-books opt-in remains available, never enabled for new users.
  bool legacyBooks = false;
  ReaderNotificationPermission permission =
      ReaderNotificationPermission.unknown;
  String? connectionError;
  Map<String, String>? pending;
  bool get available => _platform.available;
  bool get allowed => permission == ReaderNotificationPermission.allowed;
  bool isFavorite(CatalogItem item) =>
      _favorites.containsKey(notificationBase(item)) ||
      _favorites.containsKey('work_${item.id}');
  bool containsBase(String base) => _favorites.containsKey(base);

  Future<void> initialize() =>
      _initialization ??= _load().catchError((Object e, StackTrace s) {
        _initialization = null;
        Error.throwWithStackTrace(e, s);
      });
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preference);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map;
        final legacy = Map<String, String>.from(
          data['subscriptions'] as Map? ?? {},
        );
        _favorites = Map<String, String>.from(
          data['favorites'] as Map? ?? legacy,
        )..removeWhere((key, _) => !_validBase(key));
        _actual = Set<String>.from(data['actual'] as List? ?? []);
        enabled = data['enabled'] as bool? ?? true;
        asked =
            data['asked'] as bool? ?? (legacy.isNotEmpty || _actual.isNotEmpty);
        _firstReadingHandled = data['firstReadingHandled'] as bool? ?? asked;
        _favoriteNoticeShown = data['favoriteNoticeShown'] as bool? ?? false;
        legacyBooks =
            data['legacyBooks'] as bool? ?? legacy.containsKey('books');
      } on FormatException catch (_) {
        /* Corrupt optional state does not block reading. */
      } on TypeError catch (_) {
        _favorites = {};
        _actual = {};
      }
    }
    _initialized = true;
    if (available) {
      try {
        permission = await _platform.permission();
      } catch (_) {
        connectionError = tr('알림 연결을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
      if (_platform is DeviceReaderNotifications) {
        FirebaseMessaging.onMessageOpenedApp.listen(_open);
        unawaited(
          FirebaseMessaging.instance
              .getInitialMessage()
              .then((m) {
                if (m != null) _open(m);
              })
              .catchError((Object _) {}),
        );
        FirebaseMessaging.instance.onTokenRefresh.listen(
          (_) => unawaited(sync().catchError((Object _) {})),
        );
        AppLanguage.instance.addListener(_resync);
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      }
    }
    await _save();
    if (available &&
        (_favorites.isNotEmpty || _actual.isNotEmpty || legacyBooks)) {
      _resync();
    }
  }

  void _resync() => unawaited(sync().catchError((Object _) {}));
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resync();
  }

  void _open(RemoteMessage message) {
    final data = message.data.map((k, v) => MapEntry(k, '$v'));
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(data['id'] ?? '')) return;
    pending = data;
    opens.add(data);
  }

  Future<void> _save() async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      preference,
      jsonEncode({
        'favorites': _favorites,
        'actual': _actual.toList(),
        'enabled': enabled,
        'asked': asked,
        'favoriteNoticeShown': _favoriteNoticeShown,
        'firstReadingHandled': _firstReadingHandled,
        'legacyBooks': legacyBooks,
      }),
    );
    if (!ok) throw StateError(tr('알림 설정을 저장하지 못했습니다.'));
    notifyListeners();
  }

  Future<void> _change(Future<void> Function() action) {
    final next = _changes.catchError((Object _) {}).then((_) async {
      await initialize();
      await action();
    });
    _changes = next;
    return next;
  }

  bool needsReconcile(Iterable<CatalogItem> items) => items.any(
    (item) =>
        notificationBase(item) != 'work_${item.id}' &&
        _favorites.containsKey('work_${item.id}'),
  );
  Future<void> reconcile(Iterable<CatalogItem> items) async {
    var changed = false;
    await _change(() async {
      final previous = Map<String, String>.of(_favorites);
      for (final item in items) {
        final old = 'work_${item.id}', key = notificationBase(item);
        if (old != key && _favorites.containsKey(old)) {
          _favorites.putIfAbsent(key, () => item.title);
          _favorites.remove(old);
          changed = true;
        }
      }
      if (changed) {
        try {
          await _save();
        } catch (_) {
          _favorites = previous;
          rethrow;
        }
      }
    });
    if (changed && available) {
      try {
        await sync();
      } catch (_) {}
    }
  }

  Future<void> setFavorite(String base, String title, bool value) async {
    if (!_validBase(base)) throw const FormatException('Invalid favorite');
    await _change(() async {
      final previous = Map<String, String>.of(_favorites);
      if (value) {
        _favorites[base] = title;
      } else {
        _favorites.remove(base);
      }
      try {
        await _save();
      } catch (_) {
        _favorites = previous;
        rethrow;
      }
    });
    // A delivery error must never undo a locally saved favorite.
    if (available) {
      try {
        await sync();
      } catch (_) {}
    }
  }

  Future<bool> claimFavoriteNotice() async {
    var result = false;
    await _change(() async {
      if (available && (!allowed || !enabled) && !_favoriteNoticeShown) {
        _favoriteNoticeShown = true;
        // A pre-reading favorite's Later choice must not be followed by
        // another automatic prompt at the next book opening.
        _firstReadingHandled = true;
        await _save();
        result = true;
      }
    });
    return result;
  }

  Future<void> firstReading() async {
    if (!available) return;
    await initialize();
    if (!available ||
        asked ||
        _firstReadingHandled ||
        !enabled ||
        _firstReadingStarted) {
      return;
    }
    _firstReadingStarted = true;
    await _requestPermission();
    // Network/APNs synchronization must not hold the book opening screen.
    _resync();
  }

  Future<void>? _enableTask;
  Future<void> enableNotifications() => _enableTask ??= _enableNotifications()
      .whenComplete(() => _enableTask = null);
  Future<void> _enableNotifications() async {
    await _requestPermission();
    await sync();
  }

  Future<void>? _permissionTask;
  Future<void> _requestPermission() => _permissionTask ??= _change(() async {
    if (!available) throw StateError(tr('이 기기에서 알림을 설정할 수 없습니다.'));
    // Mark before requesting so repeated ready events cannot prompt twice.
    asked = true;
    _firstReadingHandled = true;
    enabled = true;
    await _save();
    if (!allowed) permission = await _platform.permission(request: true);
    await _save();
  }).whenComplete(() => _permissionTask = null);

  Future<void> disableNotifications() async {
    await _change(() async {
      enabled = false;
      await _save();
    });
    await sync();
  }

  Future<void> disableLegacyBooks() async {
    await _change(() async {
      legacyBooks = false;
      await _save();
    });
    await sync();
  }

  Future<void> openSettings() async {
    await _change(() async {
      enabled = true;
      await _save();
    });
    await _platform.openSettings();
  }

  Future<void> sync() {
    final next = _syncQueue.catchError((Object _) {}).then((_) async {
      if (!available || !_initialized) return;
      var stage = 'permission';
      try {
        permission = await _platform.permission();
        final bases = enabled && allowed
            ? {..._favorites.keys, if (legacyBooks) 'books'}
            : <String>{};
        final desired = bases
            .map((k) => notificationTopic(k, AppLanguage.instance.code))
            .toSet();
        if (desired.isNotEmpty || _actual.isNotEmpty) {
          stage = 'auto_init';
          await _platform.autoInit(true);
          stage = 'apns_registration';
          if (!await _platform.apnsReady()) {
            throw StateError(tr('알림 연결을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.'));
          }
        }
        for (final topic in _actual.difference(desired).toList()) {
          stage = 'unsubscribe';
          await _platform.unsubscribe(topic);
          _actual.remove(topic);
          await _save();
        }
        for (final topic in desired.difference(_actual).toList()) {
          stage = 'subscribe';
          await _platform.subscribe(topic);
          _actual.add(topic);
          await _save();
        }
        stage = 'auto_init_finish';
        await _platform.autoInit(desired.isNotEmpty);
        connectionError = null;
        debugPrint(
          'KoofyNotifications sync=ready subscriptions=${_actual.length}',
        );
        notifyListeners();
      } catch (e) {
        // Keep identifiers, topic names and token values out of diagnostic logs.
        final code = e is FirebaseException ? e.code : e.runtimeType;
        debugPrint('KoofyNotifications sync=failed stage=$stage code=$code');
        connectionError = tr('알림 연결을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.');
        notifyListeners();
        rethrow;
      }
    });
    _syncQueue = next;
    return next;
  }

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      AppLanguage.instance.removeListener(_resync);
    }
    super.dispose();
  }
}
