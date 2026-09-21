import 'package:flutter/material.dart';
import 'branding/startup_splash.dart';
import 'package:koofy_reader/features/ads/presentation/app_footer_ad_shell.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';
import 'package:koofy_reader/features/privacy/presentation/privacy_pages.dart';

class KoofyReaderApp extends StatefulWidget {
  const KoofyReaderApp({super.key});

  @override
  State<KoofyReaderApp> createState() => _KoofyReaderAppState();
}

class _KoofyReaderAppState extends State<KoofyReaderApp> {
  final _ads = _AdRouteObserver();
  @override
  void dispose() {
    _ads.visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Koofy Reader',
      navigatorObservers: [_ads],
      theme: KoofyTheme.forBrightness(Brightness.light),
      darkTheme: KoofyTheme.forBrightness(Brightness.dark),
      initialRoute: AppRoutes.library,
      onGenerateRoute: AppRouter.onGenerateRoute,
      builder: (context, child) {
        return StartupSplash(
          child: PrivacyGate(
            child: ValueListenableBuilder<bool>(
              valueListenable: _ads.visible,
              child: child ?? const SizedBox.shrink(),
              builder: (context, visible, navigator) =>
                  AppFooterAdShell(showFooterAd: visible, child: navigator!),
            ),
          ),
        );
      },
    );
  }
}

class _AdRouteObserver extends NavigatorObserver {
  final visible = ValueNotifier(true);
  int _revision = 0;
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    final name = topRoute.settings.name;
    final show = name != AppRoutes.reader && name != AppRoutes.nativeReader;
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted == true && revision == _revision) {
        visible.value = show;
      }
    });
  }
}
