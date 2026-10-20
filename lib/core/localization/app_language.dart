import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'messages.g.dart';

/// A missing preference means follow the device, including later OS changes.
class AppLanguage extends ChangeNotifier with WidgetsBindingObserver {
  AppLanguage();
  static final instance = AppLanguage();
  static const preferenceKey = 'app_language_v1';
  static const supported = ['ko', 'en', 'ja'];
  String? _selection;
  String _effective = 'ko';
  SharedPreferences? _preferences;
  String? get selection => _selection;
  String get code => _effective;
  Locale get locale => Locale(code);

  static String resolve(List<Locale> locales) {
    if (locales.isNotEmpty && supported.contains(locales.first.languageCode)) {
      return locales.first.languageCode;
    }
    return 'en';
  }

  Future<void> initialize({SharedPreferences? preferences}) async {
    _preferences = preferences ?? await SharedPreferences.getInstance();
    final saved = _preferences!.getString(preferenceKey);
    _selection = supported.contains(saved) ? saved : null;
    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.addObserver(this);
    _update();
  }

  Future<void> select(String? language) async {
    if (language != null && !supported.contains(language)) {
      throw ArgumentError.value(language, 'language');
    }
    final prefs = _preferences ??= await SharedPreferences.getInstance();
    final saved = language == null
        ? await prefs.remove(preferenceKey)
        : await prefs.setString(preferenceKey, language);
    if (!saved) throw StateError('Could not save language');
    _selection = language;
    _update();
  }

  void _update() {
    _effective =
        _selection ??
        resolve(WidgetsBinding.instance.platformDispatcher.locales);
    notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (_selection == null) _update();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Only app-owned message keys are translated. User books and titles stay intact.
String tr(String key, [List<Object?> arguments = const []]) =>
    translateMessage(AppLanguage.instance.code, key, arguments);

/// Translate known application errors without altering unknown diagnostic text.
String localizedError(Object error) {
  final message = switch (error) {
    FormatException e => e.message,
    StateError e => e.message,
    ArgumentError e => e.message?.toString() ?? e.toString(),
    _ => error.toString(),
  };
  return tr(message);
}

String translateMessage(
  String language,
  String key, [
  List<Object?> arguments = const [],
]) {
  final message = language == 'ko' ? key : messages[key]?[language] ?? key;
  return message.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
    final index = int.parse(match[1]!);
    return index < arguments.length ? '${arguments[index] ?? ''}' : match[0]!;
  });
}

final appContentLanguageProvider = Provider<String>((ref) {
  final language = AppLanguage.instance;
  void changed() => ref.invalidateSelf();
  language.addListener(changed);
  ref.onDispose(() => language.removeListener(changed));
  return language.code;
});
