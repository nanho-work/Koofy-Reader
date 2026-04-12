import 'dart:convert';

import 'package:koofy_reader/features/reader/domain/reader_font_keys.dart';

enum ReaderBackgroundMode { black, beige, gray }

enum ReaderFontOption { sans, serif, mono }

enum ReaderPageLayoutMode { auto, single, double }

class ReaderSettings {
  const ReaderSettings({
    required this.backgroundMode,
    required this.fontKey,
    required this.pageLayoutMode,
    required this.fontSize,
    required this.lineHeight,
    required this.horizontalPadding,
    required this.keepScreenOn,
  });

  factory ReaderSettings.defaults() {
    return const ReaderSettings(
      backgroundMode: ReaderBackgroundMode.beige,
      fontKey: ReaderFontKeys.builtinSans,
      pageLayoutMode: ReaderPageLayoutMode.auto,
      fontSize: 18,
      lineHeight: 1.7,
      horizontalPadding: 18,
      keepScreenOn: false,
    );
  }

  final ReaderBackgroundMode backgroundMode;
  final String fontKey;
  final ReaderPageLayoutMode pageLayoutMode;
  final double fontSize;
  final double lineHeight;
  final double horizontalPadding;
  final bool keepScreenOn;

  ReaderSettings copyWith({
    ReaderBackgroundMode? backgroundMode,
    String? fontKey,
    ReaderPageLayoutMode? pageLayoutMode,
    double? fontSize,
    double? lineHeight,
    double? horizontalPadding,
    bool? keepScreenOn,
  }) {
    return ReaderSettings(
      backgroundMode: backgroundMode ?? this.backgroundMode,
      fontKey: fontKey ?? this.fontKey,
      pageLayoutMode: pageLayoutMode ?? this.pageLayoutMode,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }

  String get fontFamily {
    return ReaderFontKeys.resolveFamily(fontKey);
  }

  String toRaw() {
    return jsonEncode({
      'backgroundMode': backgroundMode.name,
      'fontKey': fontKey,
      'pageLayoutMode': pageLayoutMode.name,
      'fontSize': fontSize,
      'lineHeight': lineHeight,
      'horizontalPadding': horizontalPadding,
      'keepScreenOn': keepScreenOn,
    });
  }

  static ReaderSettings? fromRaw(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      final backgroundMode = ReaderBackgroundMode.values.firstWhere(
        (value) => value.name == json['backgroundMode'],
        orElse: () => ReaderBackgroundMode.beige,
      );
      final pageLayoutMode = ReaderPageLayoutMode.values.firstWhere(
        (value) => value.name == json['pageLayoutMode'],
        orElse: () => ReaderPageLayoutMode.auto,
      );
      final fontKeyRaw = json['fontKey'];
      final legacyFontOptionRaw = json['fontOption'];
      final normalizedFontKey = _normalizeFontKey(
        fontKeyRaw: fontKeyRaw,
        legacyFontOptionRaw: legacyFontOptionRaw,
      );
      return ReaderSettings(
        backgroundMode: backgroundMode,
        fontKey: normalizedFontKey,
        pageLayoutMode: pageLayoutMode,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.7,
        horizontalPadding:
            (json['horizontalPadding'] as num?)?.toDouble() ?? 18,
        keepScreenOn: json['keepScreenOn'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  static String _normalizeFontKey({
    required Object? fontKeyRaw,
    required Object? legacyFontOptionRaw,
  }) {
    if (fontKeyRaw is String && fontKeyRaw.trim().isNotEmpty) {
      return fontKeyRaw;
    }
    final legacy = ReaderFontOption.values.firstWhere(
      (value) => value.name == legacyFontOptionRaw,
      orElse: () => ReaderFontOption.sans,
    );
    switch (legacy) {
      case ReaderFontOption.sans:
        return ReaderFontKeys.builtinSans;
      case ReaderFontOption.serif:
        return ReaderFontKeys.builtinSerif;
      case ReaderFontOption.mono:
        return ReaderFontKeys.builtinMono;
    }
  }
}
