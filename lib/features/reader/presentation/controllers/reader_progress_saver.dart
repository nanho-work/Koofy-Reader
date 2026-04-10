import 'dart:async';

class ReaderProgressSaver {
  Timer? _debounce;

  void schedule(Future<void> Function() task, {Duration? delay}) {
    _debounce?.cancel();
    _debounce = Timer(delay ?? const Duration(milliseconds: 350), () {
      unawaited(task());
    });
  }

  void cancel() {
    _debounce?.cancel();
    _debounce = null;
  }
}
