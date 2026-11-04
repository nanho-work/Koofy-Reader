import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';

String notificationBase(CatalogItem item) {
  if (item.issueMonth.isNotEmpty) return 'monthly';
  final group = item.json['translationGroupId'];
  return 'work_${group is String && group.isNotEmpty ? group : item.id}';
}

String notificationTopic(String base, String language) =>
    'reader_${base}_$language';

/// Explicit opt-in only. No permission prompt or FCM token on a fresh launch.
class ReaderNotifications extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = ReaderNotifications();
  static const preference = 'reader_notifications_v1';
  final opens = StreamController<Map<String, String>>.broadcast();
  Map<String, String> subscriptions = {};
  Set<String> _actual = {};
  Future<void> _queue = Future.value();
  bool _initialized = false;
  Map<String, String>? pending;
  bool get available => !kIsWeb && Firebase.apps.isNotEmpty;
  Future<void> initialize() async {
    if (_initialized || !available) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preference);
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map;
        subscriptions = Map<String, String>.from(
          data['subscriptions'] as Map? ?? {},
        );
        _actual = Set<String>.from(data['actual'] as List? ?? []);
      } on FormatException catch (_) {
        // A damaged local notification preference must not block reading.
      } on TypeError catch (_) {
        subscriptions = {};
        _actual = {};
      }
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    unawaited(
      FirebaseMessaging.instance
          .getInitialMessage()
          .then((message) {
            if (message != null) _open(message);
          })
          .catchError((Object _) {}),
    );
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      unawaited(sync().catchError((Object _) {}));
    });
    AppLanguage.instance.addListener(() {
      unawaited(sync().catchError((Object _) {}));
    });
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    if (subscriptions.isNotEmpty) unawaited(sync().catchError((Object _) {}));
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (subscriptions.isNotEmpty || _actual.isNotEmpty)) {
      unawaited(sync().catchError((Object _) {}));
    }
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
      jsonEncode({'subscriptions': subscriptions, 'actual': _actual.toList()}),
    );
    if (!ok) throw StateError(tr('알림 설정을 저장하지 못했습니다.'));
    notifyListeners();
  }

  Future<void> setSubscription(String base, String title, bool enabled) async {
    if (!available) throw StateError(tr('이 기기에서 알림을 설정할 수 없습니다.'));
    await initialize();
    if (enabled) {
      final permission = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        throw StateError(tr('기기 설정에서 알림을 허용해 주세요.'));
      }
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      subscriptions[base] = title;
    } else {
      subscriptions.remove(base);
    }
    await _save();
    await sync();
  }

  Future<void> sync() {
    final next = _queue.catchError((Object _) {}).then((_) async {
      if (!available) return;
      final messaging = FirebaseMessaging.instance;
      if (subscriptions.isNotEmpty) {
        await messaging.setAutoInitEnabled(true);
        if (defaultTargetPlatform == TargetPlatform.iOS &&
            await messaging.getAPNSToken() == null) {
          throw StateError(tr('알림 연결을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.'));
        }
      }
      final desired = subscriptions.keys
          .map((k) => notificationTopic(k, AppLanguage.instance.code))
          .toSet();
      for (final topic in _actual.difference(desired).toList()) {
        await messaging.unsubscribeFromTopic(topic);
        _actual.remove(topic);
        await _save();
      }
      for (final topic in desired.difference(_actual).toList()) {
        await messaging.subscribeToTopic(topic);
        _actual.add(topic);
        await _save();
      }
      if (subscriptions.isEmpty) await messaging.setAutoInitEnabled(false);
    });
    _queue = next;
    return next;
  }
}
