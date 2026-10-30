import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/data/levelplay_service.dart';
import 'package:koofy_reader/features/privacy/data/privacy_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:flutter/material.dart';
import 'branding/startup_splash.dart';
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
  final _navigatorKey = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppLanguage.instance]),
      builder: (context, _) => MaterialApp(
        locale: AppLanguage.instance.locale,
        supportedLocales: const [Locale('ko'), Locale('en'), Locale('ja')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        title: 'Koofy Reader',
        themeMode: ThemeMode.light,
        navigatorKey: _navigatorKey,
        theme: KoofyTheme.forBrightness(Brightness.light),
        darkTheme: KoofyTheme.forBrightness(Brightness.dark),
        initialRoute: AppRoutes.library,
        onGenerateRoute: AppRouter.onGenerateRoute,
        builder: (context, child) {
          return StartupSplash(
            child: StartupUpdateGate(
              child: PrivacyGate(
                navigatorKey: _navigatorKey,
                // Banners belong exclusively to the native reading viewer.
                child: Consumer(
                  builder: (context, ref, _) {
                    // Keep SDK preparation separate from ad display. The viewer
                    // can open immediately without waiting for a first SDK init.
                    final privacy = ref.watch(privacyStateProvider).valueOrNull;
                    if (privacy?.canRequestAds == true) {
                      ref.watch(levelPlayReadyProvider);
                    }
                    return child ?? const SizedBox.shrink();
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
