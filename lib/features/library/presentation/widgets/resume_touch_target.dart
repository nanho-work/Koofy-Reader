import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared three-pulse hint; remembering use never blocks opening a book.
class ResumeTouchTarget extends StatefulWidget {
  const ResumeTouchTarget({
    super.key,
    required this.onTap,
    required this.builder,
  });
  static const hintUsedKey = 'resume_cover_hint_used_v1';
  final VoidCallback? onTap;
  final Widget Function(BuildContext, VoidCallback?, Widget, bool) builder;
  @override
  State<ResumeTouchTarget> createState() => _ResumeTouchTargetState();
}

class _ResumeTouchTargetState extends State<ResumeTouchTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _loadHint();
  }

  Future<void> _loadHint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || prefs.getBool(ResumeTouchTarget.hintUsedKey) == true) {
        return;
      }
      setState(() => _showHint = true);
      if (widget.onTap != null && !MediaQuery.disableAnimationsOf(context)) {
        _pulse.repeat(count: 3);
      }
    } catch (_) {
      // A storage failure must never block opening a book.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _pulse.stop();
  }

  void _open() {
    if (widget.onTap == null) return;
    _pulse.stop();
    setState(() => _showHint = false);
    _rememberUsed();
    widget.onTap!();
  }

  Future<void> _rememberUsed() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(
        ResumeTouchTarget.hintUsedKey,
        true,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    widget.onTap == null ? null : _open,
    IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Center(
            child: Opacity(
              opacity: _pulse.isAnimating ? (1 - t) * .65 : 0,
              child: Container(
                width: 12 + 64 * t,
                height: 12 + 64 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .12),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
    _showHint,
  );
}
