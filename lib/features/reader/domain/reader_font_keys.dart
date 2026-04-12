class ReaderFontKeys {
  const ReaderFontKeys._();

  static const String builtinSans = 'builtin:sans';
  static const String builtinSerif = 'builtin:serif';
  static const String builtinMono = 'builtin:mono';

  static bool isBuiltin(String key) {
    return key == builtinSans || key == builtinSerif || key == builtinMono;
  }

  static bool isAssetKey(String key) => key.startsWith('asset:');

  static String assetKey(String assetPath) => 'asset:$assetPath';

  static String? assetPathFromKey(String key) {
    if (!isAssetKey(key)) return null;
    return key.substring('asset:'.length);
  }

  static String resolveFamily(String key) {
    switch (key) {
      case builtinSans:
        return 'sans-serif';
      case builtinSerif:
        return 'serif';
      case builtinMono:
        return 'monospace';
      default:
        final assetPath = assetPathFromKey(key);
        if (assetPath == null || assetPath.isEmpty) {
          return 'sans-serif';
        }
        return 'koofy_asset_font_${_stableHash(assetPath)}';
    }
  }

  static String displayNameFromAssetPath(String assetPath) {
    final normalized = assetPath.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final noExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return noExt.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }

  static String _stableHash(String value) {
    const int fnvOffsetBasis = 0x811C9DC5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffsetBasis;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
