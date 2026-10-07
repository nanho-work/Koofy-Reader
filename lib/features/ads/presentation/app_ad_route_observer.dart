import 'package:flutter/material.dart';
import 'package:koofy_reader/app/router.dart';

class AppAdRouteObserver extends NavigatorObserver {
  final visible = ValueNotifier(true);
  int _revision = 0;
  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    final name = topRoute.settings.name;
    final show =
        topRoute is PageRoute &&
        name != AppRoutes.reader &&
        name != AppRoutes.nativeReader;
    final revision = ++_revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator?.mounted == true && revision == _revision) {
        visible.value = show;
      }
    });
  }
}
