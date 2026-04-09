import 'dart:convert';

enum ReaderBackgroundMode { black, beige, gray }

enum ReaderFontOption { sans, serif, mono }

enum ReaderPageLayoutMode { auto, single, double }

class ReaderSettings {
  const ReaderSettings({
    required this.backgroundMode,
    required this.fontOption,
    required this.pageLayoutMode,
    required this.fontSize,
    required this.lineHeight,
    required this.horizontalPadding,
    required this.keepScreenOn,
  });

  factory ReaderSettings.defaults() {
    return const ReaderSettings(
      backgroundMode: ReaderBackgroundMode.beige,
      fontOption: ReaderFontOption.sans,
      pageLayoutMode: ReaderPageLayoutMode.auto,
      fontSize: 18,
      lineHeight: 1.7,
      horizontalPadding: 18,
      keepScreenOn: false,
    );
  }

  final ReaderBackgroundMode backgroundMode;
  final ReaderFontOption fontOption;
  final ReaderPageLayoutMode pageLayoutMode;
  final double fontSize;
  final double lineHeight;
  final double horizontalPadding;
  final bool keepScreenOn;

  ReaderSettings copyWith({
    ReaderBackgroundMode? backgroundMode,
    ReaderFontOption? fontOption,
    ReaderPageLayoutMode? pageLayoutMode,
    double? fontSize,
    double? lineHeight,
    double? horizontalPadding,
    bool? keepScreenOn,
  }) {
    return ReaderSettings(
      backgroundMode: backgroundMode ?? this.backgroundMode,
      fontOption: fontOption ?? this.fontOption,
      pageLayoutMode: pageLayoutMode ?? this.pageLayoutMode,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }

  String get fontFamily {
    switch (fontOption) {
      case ReaderFontOption.sans:
        return 'sans-serif';
      case ReaderFontOption.serif:
        return 'serif';
      case ReaderFontOption.mono:
        return 'monospace';
    }
  }

  String toRaw() {
    return jsonEncode({
      'backgroundMode': backgroundMode.name,
      'fontOption': fontOption.name,
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
      final fontOption = ReaderFontOption.values.firstWhere(
        (value) => value.name == json['fontOption'],
        orElse: () => ReaderFontOption.sans,
      );
      final pageLayoutMode = ReaderPageLayoutMode.values.firstWhere(
        (value) => value.name == json['pageLayoutMode'],
        orElse: () => ReaderPageLayoutMode.auto,
      );
      return ReaderSettings(
        backgroundMode: backgroundMode,
        fontOption: fontOption,
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
}
