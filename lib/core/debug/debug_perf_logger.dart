import 'package:flutter/foundation.dart';

class DebugPerfLogger {
  const DebugPerfLogger._();

  static void log(
    String scope,
    String event, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    if (!kDebugMode) {
      return;
    }
    final suffix = details.isEmpty
        ? ''
        : details.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join(' ');
    debugPrint(
      suffix.isEmpty
          ? '[ReaderPerf][$scope][$event]'
          : '[ReaderPerf][$scope][$event] $suffix',
    );
  }
}
