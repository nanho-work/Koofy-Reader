import 'package:flutter/material.dart';
import 'package:koofy_reader/features/ads/presentation/app_footer_ad_shell.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/core/theme/koofy_theme.dart';

class KoofyReaderApp extends StatelessWidget {
  const KoofyReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Koofy Reader',
      theme: KoofyTheme.forBrightness(Brightness.light),
      darkTheme: KoofyTheme.forBrightness(Brightness.dark),
      initialRoute: AppRoutes.library,
      onGenerateRoute: AppRouter.onGenerateRoute,
      builder: (context, child) {
        return AppFooterAdShell(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
