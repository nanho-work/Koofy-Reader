import 'package:flutter/material.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';

class AppFooterAdShell extends StatelessWidget {
  const AppFooterAdShell({
    super.key,
    required this.child,
    this.showFooterAd = true,
  });

  final Widget child;
  final bool showFooterAd;

  @override
  Widget build(BuildContext context) {
    if (!showFooterAd) {
      return child;
    }
    return Column(
      children: [
        Expanded(child: child),
        const SafeArea(top: false, child: AdFooterWidget()),
      ],
    );
  }
}
