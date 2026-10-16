import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koofy_reader/core/theme/reader_palette.dart';

/// The app shell and all routes share the same opaque canvas, including ads.
abstract final class KoofyTheme {
  static ThemeData forBrightness(Brightness brightness, {bool paper = false}) {
    final dark = brightness == Brightness.dark;
    final p = dark
        ? ReaderPalette.dark
        : paper
        ? ReaderPalette.sepia
        : ReaderPalette.light;
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
          outline: p.secondary.withValues(alpha: .25),
          outlineVariant: p.secondary.withValues(alpha: .16),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          height: 1.3,
          letterSpacing: -.3,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5),
        bodySmall: TextStyle(fontSize: 12, height: 1.4),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: .1,
        ),
      ).apply(bodyColor: p.foreground, displayColor: p.foreground),
      iconTheme: IconThemeData(color: p.foreground, size: 22),
      dividerTheme: DividerThemeData(
        color: p.secondary.withValues(alpha: .14),
        thickness: .7,
        space: 24,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: p.accent,
        collapsedIconColor: p.secondary,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.foreground,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.foreground,
          backgroundColor: p.panel.withValues(alpha: .55),
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.background,
        selectedColor: p.accent.withValues(alpha: .10),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: ThemeData(brightness: brightness).textTheme.labelLarge!
            .copyWith(
              color: p.foreground,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.panel.withValues(alpha: .65),
        hintStyle: TextStyle(color: p.secondary, fontSize: 13),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.accent.withValues(alpha: .45)),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
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
          : ReaderPalette.light.background,
      systemNavigationBarIconBrightness: dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }
}
