import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koofy_reader/core/theme/reader_palette.dart';

/// The app shell and all routes share the same opaque canvas, including ads.
abstract final class KoofyTheme {
  static ThemeData forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? ReaderPalette.dark : ReaderPalette.sepia;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
          surface: p.background,
        ).copyWith(
          onSurface: p.foreground,
          onSurfaceVariant: p.secondary,
          surfaceContainer: p.panel,
          primary: p.accent,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: systemStyle(brightness),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.background,
        selectedColor: p.panel,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static SystemUiOverlayStyle systemStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: brightness,
      systemNavigationBarColor: dark
          ? ReaderPalette.dark.background
          : ReaderPalette.sepia.background,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }
}
