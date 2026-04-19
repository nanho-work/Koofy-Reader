import 'package:koofy_reader/core/utils/hash_utils.dart';

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
        return 'koofy_asset_font_${HashUtils.fnv1a32(assetPath)}';
    }
  }

  static String displayNameFromAssetPath(String assetPath) {
    final normalized = assetPath.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final noExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return noExt.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  }
}
