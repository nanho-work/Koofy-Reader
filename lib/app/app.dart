import 'package:flutter/material.dart';
import 'package:koofy_reader/features/ads/presentation/app_footer_ad_shell.dart';
import 'package:koofy_reader/app/router.dart';

class KoofyReaderApp extends StatelessWidget {
  const KoofyReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Koofy Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1D4ED8)),
        useMaterial3: true,
      ),
      initialRoute: AppRoutes.library,
      onGenerateRoute: AppRouter.onGenerateRoute,
      builder: (context, child) {
        return AppFooterAdShell(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
