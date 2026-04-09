import 'package:flutter/material.dart';
import 'package:koofy_reader/features/reader/domain/reader_settings.dart';

const double readerDoublePageGap = 18;
const double readerVerticalPadding = 16;
const double readerContentBottomInset = 16;
const double readerFontSizeNormal = 18;
const double readerFontSizeLarge = 23;

class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.text,
    required this.panel,
    required this.divider,
  });

  final Color background;
  final Color text;
  final Color panel;
  final Color divider;
}

ReaderPalette resolveReaderPalette(ReaderBackgroundMode mode) {
  switch (mode) {
    case ReaderBackgroundMode.black:
      return const ReaderPalette(
        background: Color(0xFF111111),
        text: Color(0xFFF6F6F6),
        panel: Color(0xFF1A1A1A),
        divider: Color(0x33FFFFFF),
      );
    case ReaderBackgroundMode.beige:
      return const ReaderPalette(
        background: Color(0xFFF3EBD9),
        text: Color(0xFF2D241A),
        panel: Color(0xFFE9DFC8),
        divider: Color(0x332D241A),
      );
    case ReaderBackgroundMode.gray:
      return const ReaderPalette(
        background: Color(0xFFE2E2E2),
        text: Color(0xFF1F1F1F),
        panel: Color(0xFFD4D4D4),
        divider: Color(0x331F1F1F),
      );
  }
}
