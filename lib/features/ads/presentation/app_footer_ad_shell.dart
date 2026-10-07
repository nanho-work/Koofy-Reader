import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
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
      child: AppBannerOverlay(
        banner: showFooterAd && !hidden && privacy?.canRequestAds == true
            ? AdFooterWidget(
                key: ValueKey(privacy!.revision),
                showStatusMessages: false,
              )
            : null,
        child: child,
      ),
    );
  }
}

/// Non-reader pages fill the screen. Only the 320×50 creative occupies a
/// hit-testable overlay; transparent side margins belong to the page below.
class AppBannerOverlay extends StatelessWidget {
  const AppBannerOverlay({super.key, required this.child, this.banner});
  final Widget child;
  final Widget? banner;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final visible =
          banner != null &&
          media.viewInsets.bottom == 0 &&
          constraints.maxWidth - media.padding.horizontal >= 320;
      final clearance = visible ? 50.0 + 16 + media.padding.bottom : 0.0;
      final theme = Theme.of(context);
      return AdOverlayInsets(
        bottom: clearance,
        child: Theme(
          data: visible
              ? theme.copyWith(
                  snackBarTheme: theme.snackBarTheme.copyWith(
                    behavior: SnackBarBehavior.floating,
                    insetPadding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      clearance + 12,
                    ),
                  ),
                )
              : theme,
          child: ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child,
                if (visible)
                  Positioned(
                    left:
                        media.padding.left +
                        (constraints.maxWidth -
                                media.padding.horizontal -
                                320) /
                            2,
                    bottom: media.padding.bottom,
                    width: 320,
                    height: 50,
                    child: banner!,
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
