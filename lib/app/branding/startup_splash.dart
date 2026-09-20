import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'book_paths.dart';

/// Lives above the navigator so route changes and app resumes never replay it.
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.child});

  final Widget child;
  static const background = Color(0xFFF7F5EE);

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 800),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _finished = true);
        }
      });
  bool _started = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _finished = true;
    } else if (!_started && !_finished) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mount the library immediately so its normal loading runs during the turn.
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: !_finished,
          child: ExcludeFocus(excluding: !_finished, child: widget.child),
        ),
        if (!_finished)
          Positioned.fill(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: const SystemUiOverlayStyle(
                statusBarColor: StartupSplash.background,
                systemNavigationBarColor: StartupSplash.background,
                systemNavigationBarDividerColor: StartupSplash.background,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
                systemNavigationBarIconBrightness: Brightness.dark,
              ),
              child: BlockSemantics(
                child: AbsorbPointer(
                  child: ColoredBox(
                    key: const ValueKey('startup-splash'),
                    color: StartupSplash.background,
                    child: Center(
                      child: Semantics(
                        label: '앱 시작 중',
                        image: true,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: const Size(144, 144 * 244.0208 / 336.0227),
                            painter: BookTurnPainter(_controller),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class BookTurnPainter extends CustomPainter {
  BookTurnPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 336.0227, size.height / 244.0208);
    final ink = Paint()..color = const Color(0xFF395F47);
    for (final path in bookPaths) {
      canvas.drawPath(path, ink);
    }
    // Keep the supplied silhouette beneath one turning right page. The page
    // narrows around the spine, crosses it, then settles onto the left page.
    final t = Curves.easeInOutCubic.transform(progress.value);
    if (t > 0 && t < 1) {
      final lift = math.sin(math.pi * t);
      canvas.translate(168, 244);
      canvas.scale(math.cos(math.pi * t), 1 + 0.045 * lift);
      canvas.translate(-168, -244);
      canvas.drawPath(
        bookPaths.first,
        Paint()
          ..color = Color.lerp(
            const Color(0xFF395F47),
            const Color(0xFF83A48A),
            lift,
          )!,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BookTurnPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
