import 'package:flutter/material.dart';
import 'reader_palette.dart';

/// Opaque route canvas, shared across all Flutter pages (native reader excluded).
/// Nested scaffolds remain transparent, so tabs do not restart the gradient.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: const _AppBackgroundPainter(), child: child);
}

class _AppBackgroundPainter extends CustomPainter {
  const _AppBackgroundPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final base = ReaderPalette.light.background;
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final top = Rect.fromLTWH(0, 0, size.width, size.height * .25);
    canvas.drawRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFDCEBDD), Color(0xFFF0F4E9)],
        ).createShader(top),
    );
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            base.withValues(alpha: 0),
            base.withValues(alpha: .45),
            base,
          ],
          stops: const [0, .5, 1],
        ).createShader(top),
    );
  }

  @override
  bool shouldRepaint(_AppBackgroundPainter oldDelegate) => false;
}

/// Retains each platform's navigation animation while painting an opaque page
/// behind transparent scaffolds, preventing the previous route from bleeding in.
class AppBackgroundTransitions extends PageTransitionsBuilder {
  const AppBackgroundTransitions(this.delegate);
  final PageTransitionsBuilder delegate;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => delegate.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    AppBackground(child: child),
  );
}
