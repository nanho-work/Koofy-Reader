import 'dart:async';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';

typedef AnalyticsWriter = Future<void> Function(String, Map<String, Object>);

/// Only typed, content-free events cross this boundary. Never pass paths,
/// titles, text, locators, exception messages, or local publication IDs.
class ReaderAnalytics extends ChangeNotifier {
  ReaderAnalytics({LocalStorage? storage, this.writer})
    : _storage = storage ?? SharedPrefsLocalStorage();
  static final instance = ReaderAnalytics();
  static const choiceKey = 'reader_analytics_choice_v1';
  final LocalStorage _storage;
  final AnalyticsWriter? writer;
  FirebaseAnalytics? _sdk;
  bool loaded = false;
  bool? choice;
  bool _enabled = false;
  Future<void> _queue = Future.value();

  Future<void> initialize({bool mobile = false}) async {
    try {
      final value = await _storage.getString(choiceKey);
      choice = value == 'yes'
          ? true
          : value == 'no'
          ? false
          : null;
      if (mobile) _sdk = FirebaseAnalytics.instance;
      await _configure();
    } catch (_) {
      _enabled = false;
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> _configure() async {
    _enabled = false;
    final sdk = _sdk;
    if (sdk != null) {
      await sdk.setAnalyticsCollectionEnabled(false);
      await sdk.setConsent(
        analyticsStorageConsentGranted: choice == true,
        adStorageConsentGranted: false,
        adUserDataConsentGranted: false,
        adPersonalizationSignalsConsentGranted: false,
      );
      if (choice != true) await sdk.resetAnalyticsData();
      await sdk.setAnalyticsCollectionEnabled(choice == true);
    }
    _enabled = choice == true && (sdk != null || writer != null);
  }

  Future<void> choose(bool value) {
    // Stop accepting new events immediately, including while revoking consent.
    _enabled = false;
    final task = _queue.then((_) async {
      await _storage.setString(choiceKey, value ? 'yes' : 'no');
      choice = value;
      try {
        await _configure();
      } finally {
        notifyListeners();
      }
    });
    _queue = task.catchError((Object _) {});
    return task;
  }

  void _record(String name, [Map<String, Object> parameters = const {}]) {
    if (!_enabled) return;
    final data = <String, Object>{
      'app_language': AppLanguage.instance.code,
      ...parameters,
    };
    // SDK/network failure must never break reading or file operations.
    unawaited(
      Future<void>(() async {
        if (!_enabled) return;
        try {
          if (writer != null) {
            await writer!(name, data);
          } else {
            await _sdk?.logEvent(name: name, parameters: data);
          }
        } catch (_) {}
      }),
    );
  }

  void bookImport(String format, String result) => _record('book_import', {
    'format': const ['txt', 'epub'].contains(format) ? format : 'other',
    'result':
        const [
          'start',
          'success',
          'existing',
          'failed',
          'cancelled',
        ].contains(result)
        ? result
        : 'failed',
  });
  void download({
    required String kind,
    required String id,
    required String result,
  }) {
    if (!const ['book', 'font'].contains(kind)) return;
    _record('catalog_download', {
      'content_type': kind,
      // Public catalog ID only; never a local book ID.
      if (RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) 'content_id': id,
      'result': const ['start', 'success', 'failed'].contains(result)
          ? result
          : 'failed',
    });
  }

  void seriesOpened(String id) => _record('series_open', {
    if (RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) 'content_id': id,
  });
  void bookOpened({required bool bundled, required bool guide}) =>
      _record('book_open', {
        'source': guide
            ? 'guide'
            : bundled
            ? 'bundled'
            : 'local',
      });
  void feature(String feature) {
    if (const [
      'tts_start',
      'auto_turn_start',
      'bookmark_add',
      'font_apply',
    ].contains(feature)) {
      _record(feature);
    }
  }

  void readingTime(int seconds) {
    if (seconds > 0) {
      _record('reading_time', {'seconds': seconds.clamp(1, 86400)});
    }
  }
}
