import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:flutter/services.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/privacy/data/privacy_service.dart';

class AppFooterAdShell extends ConsumerWidget {
  const AppFooterAdShell({
    super.key,
    required this.child,
    this.showFooterAd = true,
  });

  final Widget child;
  final bool showFooterAd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacy = ref.watch(privacyStateProvider).valueOrNull;
    final hidden =
        ref.watch(adStateProvider).valueOrNull?.isBannerHidden ?? false;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: KoofyTheme.systemStyle(Theme.of(context).brightness),
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            Expanded(child: child),
            if (showFooterAd && !hidden && privacy?.canRequestAds == true)
              SafeArea(
                key: ValueKey(privacy!.revision),
                top: false,
                child: const AdFooterWidget(),
              ),
          ],
        ),
      ),
    );
  }
}
