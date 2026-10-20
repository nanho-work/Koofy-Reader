import 'dart:async';
import 'dart:convert';

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local eligibility, independent of optional Analytics consent.
class ReaderReviewService {
  ReaderReviewService({
    Future<SharedPreferences> Function()? preferences,
    Future<bool> Function()? available,
    Future<void> Function()? request,
    Future<void> Function()? openStore,
    DateTime Function()? now,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _available = available ?? InAppReview.instance.isAvailable,
       _request = request ?? InAppReview.instance.requestReview,
       _openStore =
           openStore ??
           (() =>
               InAppReview.instance.openStoreListing(appStoreId: '6814514729')),
       _now = now ?? DateTime.now;

  static final instance = ReaderReviewService();
  static const storageKey = 'reader_review_usage_v1';
  static const threshold = Duration(hours: 5);
  static const cooldown = Duration(days: 90);
  final Future<SharedPreferences> Function() _preferences;
  final Future<bool> Function() _available;
  final Future<void> Function() _request;
  final Future<void> Function() _openStore;
  final DateTime Function() _now;
  Future<void> _queue = Future<void>.value();

  Future<void> _serialize(Future<void> Function() action) {
    // Plugin/storage failure must never interrupt reading or navigation.
    return _queue = _queue.then((_) => action()).catchError((Object _) {});
  }

  Map<String, dynamic> _read(SharedPreferences prefs) {
    final raw = prefs.getString(storageKey);
    return raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> addReadingTime(Duration duration) => _serialize(() async {
    if (duration.inMilliseconds <= 0) return;
    final prefs = await _preferences();
    final state = _read(prefs);
    state['milliseconds'] =
        (state['milliseconds'] as int? ?? 0) + duration.inMilliseconds;
    await prefs.setString(storageKey, jsonEncode(state));
  });

  Future<void> maybeRequest({
    required bool Function() canShow,
  }) => _serialize(() async {
    if (!canShow()) return;
    final prefs = await _preferences();
    final state = _read(prefs);
    if ((state['milliseconds'] as int? ?? 0) < threshold.inMilliseconds) return;
    final last = state['lastRequestMs'] as int?;
    final now = _now().millisecondsSinceEpoch;
    if (last != null && now - last < cooldown.inMilliseconds) return;
    if (!await _available() || !canShow()) return;
    // Store the attempt before invoking the OS. No API reports review completion.
    state['lastRequestMs'] = now;
    if (!await prefs.setString(storageKey, jsonEncode(state))) return;
    if (canShow()) await _request();
  });

  Future<bool> openStore() async {
    try {
      await _openStore();
      return true;
    } catch (_) {
      return false;
    }
  }
}
