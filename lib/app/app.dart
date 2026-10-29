import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:koofy_reader/core/theme/app_appearance.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'package:koofy_reader/features/ads/presentation/app_ad_route_observer.dart';
import 'branding/startup_splash.dart';
import 'package:koofy_reader/features/ads/presentation/app_footer_ad_shell.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';
import 'package:koofy_reader/features/privacy/presentation/privacy_pages.dart';
import 'package:koofy_reader/features/updates/presentation/startup_update_gate.dart';

class KoofyReaderApp extends StatefulWidget {
  const KoofyReaderApp({super.key});

  @override
  State<KoofyReaderApp> createState() => _KoofyReaderAppState();
}

class _KoofyReaderAppState extends State<KoofyReaderApp> {
  final _ads = AppAdRouteObserver();
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  void dispose() {
    _ads.visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppLanguage.instance,
        AppAppearance.instance,
      ]),
      builder: (context, _) => MaterialApp(
        locale: AppLanguage.instance.locale,
        supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        title: 'Koofy Reader',
        themeMode: AppAppearance.instance.mode,
        navigatorObservers: [_ads],
        navigatorKey: _navigatorKey,
        theme: KoofyTheme.forBrightness(
          Brightness.light,
          paper: AppAppearance.instance.selection == 'sepia',
        ),
        darkTheme: KoofyTheme.forBrightness(Brightness.dark),
        initialRoute: AppRoutes.library,
        onGenerateRoute: AppRouter.onGenerateRoute,
        builder: (context, child) {
          return StartupSplash(
            child: StartupUpdateGate(
              child: PrivacyGate(
                navigatorKey: _navigatorKey,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _ads.visible,
                  child: child ?? const SizedBox.shrink(),
                  builder: (context, visible, navigator) => AppFooterAdShell(
                    showFooterAd: visible,
                    child: navigator!,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
