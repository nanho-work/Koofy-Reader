import 'package:flutter/widgets.dart';

const catalogSidebarWidth = 172.0;
const catalogSidebarBreakpoint = 600.0;

/// Available logical width after safe areas; shared by books, library,
/// settings and series details, including resized and rotated windows.
bool usesReaderSidebar(double availableWidth) =>
    availableWidth >= catalogSidebarBreakpoint;
const bookShelfHorizontalPadding = 16.0;
const bookShelfSpacing = 14.0;

/// Uses logical window geometry, never a device name or physical pixel count.
/// The shelf width already excludes category navigation and safe-area padding.
int catalogShelfColumns({
  required Size window,
  required double shelfWidth,
  required double textScale,
}) {
  final expanded = window.shortestSide >= 600;
  final landscape = window.width / window.height >= 1.28;
  final target = expanded
      ? (landscape
            ? (window.width >= 1200 ? 6 : 5)
            : (window.width >= 1000 ? 5 : 4))
      : (window.width >= 600 ? 4 : 3);
  final minimumWidth = 96 * textScale.clamp(1.0, 2.0);
  final fitting =
      ((shelfWidth + bookShelfSpacing) / (minimumWidth + bookShelfSpacing))
          .floor();
  return fitting.clamp(1, target);
}
