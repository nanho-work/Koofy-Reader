import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/reader/domain/reader_font_keys.dart';

final readerFontRegistryProvider = Provider<ReaderFontRegistry>(
  (ref) => ReaderFontRegistry(),
);

class ReaderFontItem {
  const ReaderFontItem({
    required this.key,
    required this.label,
    required this.previewFamily,
    required this.isCustom,
  });

  final String key;
  final String label;
  final String previewFamily;
  final bool isCustom;
}

class ReaderFontRegistry {
  List<ReaderFontItem>? _cachedItems;
  static final Set<String> _loadedFamilies = <String>{};

  Future<List<ReaderFontItem>> loadAvailableFonts() async {
    if (_cachedItems != null) {
      return _cachedItems!;
    }

    final items = <ReaderFontItem>[
      ReaderFontItem(
        key: ReaderFontKeys.builtinSans,
        label: '기본 Sans',
        previewFamily: ReaderFontKeys.resolveFamily(ReaderFontKeys.builtinSans),
        isCustom: false,
      ),
      ReaderFontItem(
        key: ReaderFontKeys.builtinSerif,
        label: '기본 Serif',
        previewFamily: ReaderFontKeys.resolveFamily(
          ReaderFontKeys.builtinSerif,
        ),
        isCustom: false,
      ),
      ReaderFontItem(
        key: ReaderFontKeys.builtinMono,
        label: '기본 Mono',
        previewFamily: ReaderFontKeys.resolveFamily(ReaderFontKeys.builtinMono),
        isCustom: false,
      ),
    ];

    final customAssets = await _loadFontAssetPaths();
    for (final assetPath in customAssets) {
      final key = ReaderFontKeys.assetKey(assetPath);
      final family = ReaderFontKeys.resolveFamily(key);
      await _ensureAssetLoaded(assetPath, family);
      items.add(
        ReaderFontItem(
          key: key,
          label: ReaderFontKeys.displayNameFromAssetPath(assetPath),
          previewFamily: family,
          isCustom: true,
        ),
      );
    }

    _cachedItems = items;
    return items;
  }

  Future<void> ensureLoadedForKey(String fontKey) async {
    final assetPath = ReaderFontKeys.assetPathFromKey(fontKey);
    if (assetPath == null || assetPath.isEmpty) {
      return;
    }
    final family = ReaderFontKeys.resolveFamily(fontKey);
    await _ensureAssetLoaded(assetPath, family);
  }

  Future<List<String>> _loadFontAssetPaths() async {
    try {
      final raw = await rootBundle.loadString('AssetManifest.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const <String>[];
      }
      final result =
          decoded.keys
              .where((path) => path.startsWith('assets/fonts/'))
              .where((path) => path.toLowerCase().endsWith('.ttf'))
              .toList()
            ..sort();
      return result;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _ensureAssetLoaded(String assetPath, String family) async {
    if (_loadedFamilies.contains(family)) {
      return;
    }
    try {
      final loader = FontLoader(family);
      loader.addFont(rootBundle.load(assetPath));
      await loader.load();
      _loadedFamilies.add(family);
    } catch (_) {
      // Ignore malformed/missing font files and keep fallback font.
    }
  }
}
