import 'dart:async';

import '../connection_settings.dart';
import '../connection_state.dart';
import '../core.dart';
import '../fast/row_view.dart';
import '../results.dart';
import '../to_statement.dart';
import '../transaction_context.dart';
import 'pool.dart';

export 'pool.dart' show PoolQueueFullException;

/// A bounded pool of physical PostgreSQL connections.
///
/// Every operation owns one specific connection for its complete lifetime.
/// Prepared statement caches therefore remain connection-local and two
/// concurrent operations are never accidentally assigned the same socket.
class PostgreSqlPool {
  PostgreSqlPool(
    this.size,
    this.connectionInfo, {
    this.allowAttemptToReconnect = false,
    this.timeout = defaultTimeout,
    this.maxPendingOperations = defaultMaxPendingOperations,
  })  : _permits = Pool(size,
            timeout: timeout, maxPending: maxPendingOperations),
        _connectionMutex =
            Pool(1, maxPending: size > 1 ? size - 1 : 0) {
    if (size <= 0) {
      throw RangeError.value(size, 'size', 'Must be greater than zero.');
    }
  }

  static const defaultTimeout = Duration(seconds: 300);
  static const defaultMaxPendingOperations = 1024;

  final int size;
  final ConnectionSettings connectionInfo;
  final bool allowAttemptToReconnect;
  final Duration timeout;
  final int maxPendingOperations;
  final Pool _permits;
  final Pool _connectionMutex;
  final List<CoreConnection> _connections = <CoreConnection>[];
  final List<bool> _leased = <bool>[];
  int _cursor = 0;
  bool _closed = false;
  Future<void>? _closeFuture;
  int _operationTimeoutCount = 0;
  int _connectionReplacementCount = 0;
  int _connectionReplacementFailureCount = 0;

  /// Physical sockets currently retained by this pool; never exceeds [size].
  int get openConnectionCount => _connections
      .where(
          (connection) => connection.connectionState != ConnectionState.closed)
      .length;

  /// Operations that currently own one of the fixed connection slots.
  int get leasedConnectionCount => _permits.inUse;

  /// Operations waiting for a slot. These do not open additional sockets.
  int get pendingOperationCount => _permits.pendingCount;

  /// Operations rejected before execution because the bounded FIFO was full.
  int get rejectedOperationCount => _permits.rejectedCount;

  /// Accepted operations that expired while waiting for a connection slot.
  int get queuedOperationTimeoutCount => _permits.timedOutCount;

  /// Running operations whose execution deadline expired.
  int get operationTimeoutCount => _operationTimeoutCount;

  /// Closed or invalid physical connections replaced successfully in-place.
  int get connectionReplacementCount => _connectionReplacementCount;

  /// In-place replacement attempts that could not open a new connection.
  int get connectionReplacementFailureCount =>
      _connectionReplacementFailureCount;

  Future<CoreConnection> _newConnection(int index) async {
    final settings = connectionInfo.clone();
    settings.connectionName = 'pool_connection_$index';
    settings.allowAttemptToReconnect = allowAttemptToReconnect;
    final connection = CoreConnection.fromSettings(settings);
    if (allowAttemptToReconnect) {
      await connection.tryReconnect();
    } else {
      await connection.connect();
    }
    return connection;
  }

  Future<void> _open() async {
    if (_connections.isNotEmpty) return;
    if (_closed) throw StateError('PostgreSQL pool is closed.');

    final created = <CoreConnection>[];
    try {
      final futures = List<Future<CoreConnection>>.generate(size, (index) async {
        final connection = await _newConnection(index);
        created.add(connection);
        return connection;
      }, growable: false);
      _connections.addAll(await Future.wait(futures));
      _leased.addAll(List<bool>.filled(size, false));
    } catch (_) {
      await Future.wait(created.map((connection) => connection.close()));
      rethrow;
    }
  }

  Future<_ConnectionLease> _leaseConnection() {
    return _connectionMutex.withResource(() async {
      await _open();
      for (var offset = 0; offset < size; offset++) {
        final index = (_cursor + offset) % size;
        if (_leased[index]) continue;
        _leased[index] = true;
        _cursor = (index + 1) % size;
        try {
          var connection = _connections[index];
          if (connection.connectionState == ConnectionState.closed) {
            connection = await _replaceConnection(index, connection);
          } else if (connection.connectionState ==
                  ConnectionState.socketConnecting ||
              connection.connectionState == ConnectionState.authenticating) {
            await connection.whenConnected;
          }
          return _ConnectionLease(index, connection);
        } catch (_) {
          _leased[index] = false;
          rethrow;
        }
      }
      throw StateError('Pool permit/connection lease invariant violated.');
    });
  }

  Future<CoreConnection> _replaceConnection(
      int index, CoreConnection previous) async {
    await previous.close();
    if (_closed) throw StateError('PostgreSQL pool is closed.');
    try {
      final replacement = await _newConnection(index);
      _connections[index] = replacement;
      _connectionReplacementCount++;
      return replacement;
    } catch (_) {
      _connectionReplacementFailureCount++;
      rethrow;
    }
  }

  Future<T> _run<T>(Future<T> Function(CoreConnection connection) action,
      {Duration? operationTimeout}) {
    final effectiveTimeout = operationTimeout ?? timeout;
    if (effectiveTimeout <= Duration.zero) {
      return Future<T>.error(ArgumentError.value(
          effectiveTimeout, 'operationTimeout', 'Must be greater than zero.'));
    }
    final result = Completer<T>();
    unawaited(_runGuarded(action, result, effectiveTimeout));
    return result.future;
  }

  Future<void> _runGuarded<T>(
    Future<T> Function(CoreConnection connection) action,
    Completer<T> result,
    Duration operationTimeout,
  ) async {
    try {
      final outcome = await _permits.withResource(() async {
        return _runWithLease(action, result, operationTimeout);
      });
      if (outcome != null && !result.isCompleted) outcome.complete(result);
    } catch (error, stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }
  }

  Future<_PoolOperationOutcome<T>?> _runWithLease<T>(
    Future<T> Function(CoreConnection connection) action,
    Completer<T> result,
    Duration operationTimeout,
  ) async {
    final settled = Completer<void>();
    final firstEvent = Completer<void>();
    var timedOut = false;
    _PoolOperationOutcome<T>? outcome;

    final lease = await _leaseConnection();
    try {
      Future<T>.sync(() => action(lease.connection)).then((value) {
        outcome = _PoolOperationValue<T>(value);
        settled.complete();
        if (!firstEvent.isCompleted) firstEvent.complete();
      }, onError: (Object error, StackTrace stackTrace) {
        outcome = _PoolOperationError<T>(error, stackTrace);
        settled.complete();
        if (!firstEvent.isCompleted) firstEvent.complete();
      });

      final timer = Timer(operationTimeout, () {
        if (settled.isCompleted) return;
        timedOut = true;
        _operationTimeoutCount++;
        if (!result.isCompleted) {
          result.completeError(
            TimeoutException(
              'PostgreSQL pool operation timed out after $operationTimeout.',
              operationTimeout,
            ),
            StackTrace.current,
          );
        }
        firstEvent.complete();
      });

      await firstEvent.future;
      timer.cancel();

      if (timedOut) {
        await _retireTimedOutConnection(lease, settled.future);
        return null;
      }
      return outcome!;
    } finally {
      _leased[lease.index] = false;
    }
  }

  Future<void> _retireTimedOutConnection(
      _ConnectionLease lease, Future<void> operationSettled) async {
    try {
      await lease.connection.close();
    } catch (_) {
      // CoreConnection marks itself closed before flushing/destroying, so the
      // slot remains unusable even if close reports an error.
    }

    // Closing a socket normally settles protocol futures immediately. A user
    // transaction callback may still be running, however, and the lease must
    // remain held until that Future actually completes.
    await operationSettled;

    if (_closed) return;
    try {
      await _replaceConnection(lease.index, lease.connection);
    } catch (_) {
      // The closed connection stays in its slot. The next lease will retry an
      // in-place replacement; it can never reuse the timed-out socket.
    }
  }

  Future<int> execute(String sql, {Duration? timeout}) =>
      _run((connection) => connection.execute(sql), operationTimeout: timeout);

  Future<Results> querySimple(String sql, {Duration? timeout}) => _run(
      (connection) => connection.querySimple(sql),
      operationTimeout: timeout);

  Future<Results> queryUnnamed(
    String sql,
    dynamic params, {
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool isDeallocate = false,
    Duration? timeout,
  }) =>
      _run(
        (connection) => connection.queryUnnamed(
          sql,
          params,
          placeholderIdentifier: placeholderIdentifier,
          isDeallocate: isDeallocate,
        ),
        operationTimeout: timeout,
      );

  Future<Results> queryNamed(
    String sql,
    dynamic params, {
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool isDeallocate = false,
    Duration? timeout,
  }) =>
      _run(
        (connection) => connection.queryNamed(
          sql,
          params,
          placeholderIdentifier: placeholderIdentifier,
          isDeallocate: isDeallocate,
        ),
        operationTimeout: timeout,
      );

  Future<List<Map<String, dynamic>>> queryMaps(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) =>
      _run((connection) => connection.queryMaps(sql,
          params: params,
          placeholderIdentifier: placeholderIdentifier,
          requireBinaryResults: requireBinaryResults));

  Future<List<T>> queryTyped<T>(
    String sql,
    T Function(RowView row) mapper, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) =>
      _run((connection) => connection.queryTyped<T>(sql, mapper,
          params: params,
          placeholderIdentifier: placeholderIdentifier,
          requireBinaryResults: requireBinaryResults));

  Future<void> queryEach(
    String sql,
    void Function(RowView row) onRow, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) =>
      _run((connection) => connection.queryEach(sql, onRow,
          params: params,
          placeholderIdentifier: placeholderIdentifier,
          requireBinaryResults: requireBinaryResults));

  Future<Results> queryCached(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) =>
      _run((connection) => connection.queryCached(sql,
          params: params,
          placeholderIdentifier: placeholderIdentifier,
          requireBinaryResults: requireBinaryResults));

  Future<T> runInTransaction<T>(
    Future<T> Function(TransactionContext context) operation, {
    Duration? timeout,
  }) =>
      _run(
        (connection) => connection.runInTransaction(operation),
        operationTimeout: timeout,
      );

  Future<void> close() {
    final current = _closeFuture;
    if (current != null) return current;
    final closing = _close();
    _closeFuture = closing;
    return closing;
  }

  Future<void> _close() async {
    _closed = true;
    await _permits.close();
    await _connectionMutex.close();
    await Future.wait(_connections.map((connection) => connection.close()));
    _connections.clear();
    _leased.clear();
  }
}

class _ConnectionLease {
  const _ConnectionLease(this.index, this.connection);

  final int index;
  final CoreConnection connection;
}

abstract class _PoolOperationOutcome<T> {
  void complete(Completer<T> completer);
}

class _PoolOperationValue<T> implements _PoolOperationOutcome<T> {
  const _PoolOperationValue(this.value);

  final T value;

  @override
  void complete(Completer<T> completer) => completer.complete(value);
}

class _PoolOperationError<T> implements _PoolOperationOutcome<T> {
  const _PoolOperationError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;

  @override
  void complete(Completer<T> completer) =>
      completer.completeError(error, stackTrace);
}
