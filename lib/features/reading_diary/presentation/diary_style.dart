import 'package:flutter/material.dart';

/// Shared rhythm for calendar, history and charts; no platform-specific decoration.
abstract final class DiaryStyle {
  static const maxWidth = 1040.0;
  static const ink = Color(0xFF293C33);
  static const green = Color(0xFF486852);
  static const muted = Color(0xFF737C74);
  static const sunday = Color(0xFFB75550);
  static const saturday = Color(0xFF527AA3);
  static const rule = Color(0x19727E70);
  static Duration motion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 180);
}

class DiaryToolButton extends StatelessWidget {
  const DiaryToolButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      foregroundColor: DiaryStyle.ink,
      disabledForegroundColor: DiaryStyle.muted.withValues(alpha: .35),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.all(10),
    ),
    icon: Icon(icon, size: 22),
  );
}
