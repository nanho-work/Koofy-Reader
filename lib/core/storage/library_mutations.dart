import 'dart:async';

/// A single application-isolate boundary for library metadata mutations, including
/// restore. Nested repository calls share the lock; a failed write cannot poison it.
class LibraryMutations {
  static final _zoneKey = Object();
  static Future<void>? _pending;

  static Future<T> run<T>(Future<T> Function() operation) {
    final active = Zone.current[_zoneKey];
    if (active is _Lease && active.active) return operation();
    final previous = _pending;
    final completion = Completer<void>();
    _pending = completion.future;
    Future<T> execute() async {
      final lease = _Lease();
      try {
        return await runZoned(operation, zoneValues: {_zoneKey: lease});
      } finally {
        lease.active = false;
        if (identical(_pending, completion.future)) _pending = null;
        completion.complete();
      }
    }

    return previous == null ? execute() : previous.then((_) => execute());
  }
}

class _Lease {
  bool active = true;
}
