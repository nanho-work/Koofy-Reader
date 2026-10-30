import 'dart:async';
import 'package:flutter/material.dart';
import 'package:koofy_reader/core/localization/app_language.dart';

/// Counts down from the persisted expiry, including time spent outside the app.
class RewardAdButton extends StatefulWidget {
  const RewardAdButton({
    super.key,
    this.hiddenUntil,
    required this.busy,
    required this.onPressed,
    this.now = DateTime.now,
  });
  final DateTime? hiddenUntil;
  final bool busy;
  final VoidCallback onPressed;
  final DateTime Function() now;

  @override
  State<RewardAdButton> createState() => _RewardAdButtonState();
}

class _RewardAdButtonState extends State<RewardAdButton>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.hiddenUntil?.isAfter(widget.now()) ?? false) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!(widget.hiddenUntil?.isAfter(widget.now()) ?? false)) {
          _timer?.cancel();
        }
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(covariant RewardAdButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hiddenUntil != widget.hiddenUntil) _startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      setState(() {});
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final milliseconds =
        widget.hiddenUntil?.difference(widget.now()).inMilliseconds ?? 0;
    final seconds = milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
    final hidden = seconds > 0;
    String digits(int value) => value.toString().padLeft(2, '0');
    final countdown =
        '${digits(seconds ~/ 3600)}:${digits(seconds ~/ 60 % 60)}:${digits(seconds % 60)}';
    return FilledButton(
      onPressed: widget.busy || hidden ? null : widget.onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              excluding: hidden,
              child: Opacity(
                opacity: hidden ? 0 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    widget.busy ? tr('처리 중…') : tr('광고 보고 4시간 광고 없이 읽기'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            if (hidden)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('광고 숨김 적용 중'), textAlign: TextAlign.center),
                    Text(
                      countdown,
                      key: const ValueKey('ad-reward-countdown'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
