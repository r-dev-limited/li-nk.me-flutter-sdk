import 'dart:async';

/// Owns an entire asynchronous HTTP operation, including its response stream.
/// A transport that ignores abort may finish later, but cannot settle twice.
class RequestScope {
  final Set<_Pending<dynamic>> _pending = <_Pending<dynamic>>{};

  Future<T?> run<T>(
    Duration deadline,
    Future<T> Function(RequestCancellation cancellation) operation,
  ) {
    final pending = _Pending<T>();
    _pending.add(pending);
    pending.timer = Timer(deadline, () => _finish(pending, null));
    scheduleMicrotask(() {
      if (!_pending.contains(pending)) return;
      Future<T>.sync(() => operation(pending.cancellation)).then(
        (value) => _finish(pending, value),
        onError: (Object _, StackTrace _) => _finish(pending, null),
      );
    });
    return pending.result.future;
  }

  void cancelAll() {
    for (final pending in _pending.toList()) {
      _finish(pending, null);
    }
  }

  void _finish<T>(_Pending<T> pending, T? value) {
    if (!_pending.remove(pending)) return;
    pending.timer?.cancel();
    pending.result.complete(value);
    pending.cancellation.close();
  }
}

class RequestCancellation {
  final Completer<void> _abort = Completer<void>();
  final List<void Function()> _cleanup = <void Function()>[];
  bool get isClosed => _abort.isCompleted;
  Future<void> get whenClosed => _abort.future;

  void onClose(void Function() cleanup) {
    if (isClosed) {
      _run(cleanup);
    } else {
      _cleanup.add(cleanup);
    }
  }

  void close() {
    if (isClosed) return;
    _abort.complete();
    final cleanup = _cleanup.toList();
    _cleanup.clear();
    for (final operation in cleanup) {
      _run(operation);
    }
  }

  void _run(void Function() operation) {
    try {
      operation();
    } catch (_) {
      // Cleanup cannot prevent the caller from settling at its deadline.
    }
  }
}

class _Pending<T> {
  final Completer<T?> result = Completer<T?>();
  final RequestCancellation cancellation = RequestCancellation();
  Timer? timer;
}
