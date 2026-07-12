import 'dart:async';
import 'dart:collection';

/// A small FIFO concurrency limiter used by the PostgreSQL connection pool.
///
/// The timeout applies only while an operation is waiting for a slot. Running
/// operations are never interrupted by this class.
class Pool {
  static final Stopwatch _clock = Stopwatch()..start();

  final int _capacity;
  final Duration? _timeout;
  final int _maxPending;
  final Queue<_PoolWaiter> _waiters = ListQueue<_PoolWaiter>();

  int _inUse = 0;
  int _rejectedCount = 0;
  int _timedOutCount = 0;
  bool _isClosed = false;
  Timer? _timer;
  Completer<void>? _closeCompleter;

  Pool(int capacity, {Duration? timeout, int maxPending = 1024})
      : _capacity = capacity,
        _timeout = timeout,
        _maxPending = maxPending {
    if (capacity <= 0) {
      throw ArgumentError.value(
          capacity, 'capacity', 'Must be greater than zero.');
    }
    if (maxPending < 0) {
      throw ArgumentError.value(
          maxPending, 'maxPending', 'Must be greater than or equal to zero.');
    }
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(
          timeout, 'timeout', 'Must be greater than zero.');
    }
  }

  int get capacity => _capacity;
  int get inUse => _inUse;
  int get pendingCount => _waiters.length;
  int get maxPending => _maxPending;
  int get rejectedCount => _rejectedCount;
  int get timedOutCount => _timedOutCount;
  bool get isClosed => _isClosed;

  /// Runs [callback] once one of the pool's slots is available.
  ///
  /// Slots are granted in request order and are always returned, including
  /// when [callback] throws or returns a future that completes with an error.
  Future<T> withResource<T>(FutureOr<T> Function() callback) async {
    final wait = _acquire();
    if (wait != null) await wait;

    try {
      return await callback();
    } finally {
      _release();
    }
  }

  /// Stops accepting work and completes after all already accepted work ends.
  ///
  /// Calls made more than once return the same future. Work already waiting in
  /// the FIFO remains valid and is allowed to run.
  Future<void> close() {
    final current = _closeCompleter;
    if (current != null) return current.future;

    _isClosed = true;
    final completer = Completer<void>();
    _closeCompleter = completer;
    _completeCloseIfIdle();
    return completer.future;
  }

  Future<void>? _acquire() {
    if (_isClosed) {
      throw StateError('withResource() may not be called on a closed Pool.');
    }

    if (_inUse < _capacity) {
      _inUse++;
      return null;
    }

    if (_waiters.length >= _maxPending) {
      _rejectedCount++;
      throw PoolQueueFullException(
        capacity: _capacity,
        maxPending: _maxPending,
        pendingCount: _waiters.length,
        rejectedCount: _rejectedCount,
      );
    }

    final completer = Completer<void>();
    final timeout = _timeout;
    final deadline = timeout == null
        ? null
        : _clock.elapsedMicroseconds + timeout.inMicroseconds;
    final wasEmpty = _waiters.isEmpty;
    _waiters.addLast(_PoolWaiter(completer, deadline));
    if (wasEmpty) _scheduleHeadTimeout();
    return completer.future;
  }

  void _release() {
    if (_inUse <= 0) {
      throw StateError('Pool slot released more than once.');
    }

    // Keep the common uncontended path free of clock reads and allocations.
    if (_waiters.isEmpty) {
      _inUse--;
      _completeCloseIfIdle();
      return;
    }

    if (_timeout == null) {
      final waiter = _waiters.removeFirst();
      waiter.completer.complete();
      return;
    }

    final now = _clock.elapsedMicroseconds;
    while (_waiters.isNotEmpty) {
      final waiter = _waiters.removeFirst();
      final deadline = waiter.deadline;
      if (deadline != null && deadline <= now) {
        _timedOutCount++;
        waiter.completer.completeError(_timeoutError(), StackTrace.current);
        continue;
      }

      // The released slot is transferred directly to the oldest waiter, so
      // _inUse does not change here.
      _scheduleHeadTimeout();
      waiter.completer.complete();
      return;
    }

    _cancelTimer();
    _inUse--;
    _completeCloseIfIdle();
  }

  void _onTimeout() {
    _timer = null;
    final now = _clock.elapsedMicroseconds;

    while (_waiters.isNotEmpty) {
      final waiter = _waiters.first;
      final deadline = waiter.deadline;
      if (deadline == null || deadline > now) break;
      _waiters.removeFirst();
      _timedOutCount++;
      waiter.completer.completeError(_timeoutError(), StackTrace.current);
    }

    _scheduleHeadTimeout();
  }

  void _scheduleHeadTimeout() {
    _cancelTimer();
    if (_waiters.isEmpty) return;

    final deadline = _waiters.first.deadline;
    if (deadline == null) return;
    final remaining = deadline - _clock.elapsedMicroseconds;
    _timer = Timer(
        remaining <= 0 ? Duration.zero : Duration(microseconds: remaining),
        _onTimeout);
  }

  TimeoutException _timeoutError() => TimeoutException(
        'Pool wait timed out while all resources were leased.',
        _timeout,
      );

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _completeCloseIfIdle() {
    final completer = _closeCompleter;
    if (completer == null || completer.isCompleted) return;
    if (_inUse != 0 || _waiters.isNotEmpty) return;
    _cancelTimer();
    completer.complete();
  }
}

/// Thrown before an operation is accepted when the bounded FIFO is full.
///
/// Rejection never consumes a resource slot and never invokes the operation.
class PoolQueueFullException implements Exception {
  const PoolQueueFullException({
    required this.capacity,
    required this.maxPending,
    required this.pendingCount,
    required this.rejectedCount,
  });

  final int capacity;
  final int maxPending;
  final int pendingCount;
  final int rejectedCount;

  @override
  String toString() =>
      'PoolQueueFullException: pool capacity $capacity is fully leased and '
      'the pending-operation limit $maxPending has been reached '
      '(rejection #$rejectedCount).';
}

class _PoolWaiter {
  final Completer<void> completer;
  final int? deadline;

  _PoolWaiter(this.completer, this.deadline);
}
