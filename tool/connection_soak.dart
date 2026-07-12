import 'dart:io';

import 'package:dargres/dargres.dart';

Future<void> main(List<String> arguments) async {
  final options = _SoakOptions.parse(arguments, Platform.environment);
  final pool = PostgreSqlPool(
    options.poolSize,
    ConnectionSettings(
      user: options.user,
      password: options.password,
      database: options.database,
      host: options.host,
      port: options.port,
      applicationName: 'dargres_connection_soak',
      allowAttemptToReconnect: true,
      tcpKeepalive: true,
    ),
    allowAttemptToReconnect: true,
    timeout: options.operationTimeout,
    maxPendingOperations: options.concurrency,
  );
  final clock = Stopwatch()..start();
  var operations = 0;
  var errors = 0;
  var checksum = 0;
  var stop = false;
  var lastOperations = 0;
  var lastReport = Duration.zero;

  final reporter = Stream<void>.periodic(options.reportEvery).listen((_) {
    final elapsed = clock.elapsed;
    final intervalSeconds =
        (elapsed - lastReport).inMicroseconds / Duration.microsecondsPerSecond;
    final intervalOperations = operations - lastOperations;
    final rate = intervalSeconds == 0 ? 0 : intervalOperations / intervalSeconds;
    stdout.writeln(
      'elapsed=${elapsed.inSeconds}s operations=$operations '
      'rate=${rate.toStringAsFixed(0)}/s errors=$errors '
      'connections=${pool.openConnectionCount}/${pool.size} '
      'leased=${pool.leasedConnectionCount} queued=${pool.pendingOperationCount} '
      'rejected=${pool.rejectedOperationCount} '
      'queueTimeouts=${pool.queuedOperationTimeoutCount} '
      'operationTimeouts=${pool.operationTimeoutCount} '
      'replacements=${pool.connectionReplacementCount} '
      'rssMiB=${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1)}',
    );
    lastOperations = operations;
    lastReport = elapsed;
  });

  Object? failure;
  StackTrace? failureStackTrace;
  try {
    await Future.wait(
      List<Future<void>>.generate(
        options.concurrency,
        (worker) async {
          while (!stop && clock.elapsed < options.duration) {
            try {
              final rows = await pool.queryMaps(
                r'SELECT $1::int4 AS worker_id, pg_backend_pid() AS backend_pid',
                params: <Object?>[worker],
              );
              final row = rows.single;
              if (row['worker_id'] != worker || row['backend_pid'] is! int) {
                throw StateError('Unexpected result for worker $worker: $row');
              }
              operations++;
              checksum = (checksum ^ (row['backend_pid'] as int)) & 0x7fffffff;
            } catch (_) {
              errors++;
              stop = true;
              rethrow;
            }
          }
        },
        growable: false,
      ),
    );
  } catch (error, stackTrace) {
    failure = error;
    failureStackTrace = stackTrace;
  } finally {
    await reporter.cancel();
    await pool.close();
    clock.stop();
  }

  stdout.writeln(
    'complete elapsed=${clock.elapsed.inMilliseconds}ms operations=$operations '
    'errors=$errors checksum=$checksum '
    'rejected=${pool.rejectedOperationCount} '
    'queueTimeouts=${pool.queuedOperationTimeoutCount} '
    'operationTimeouts=${pool.operationTimeoutCount} '
    'replacements=${pool.connectionReplacementCount} '
    'rssMiB=${(ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1)}',
  );
  if (failure != null) Error.throwWithStackTrace(failure, failureStackTrace!);
}

class _SoakOptions {
  const _SoakOptions({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.password,
    required this.poolSize,
    required this.concurrency,
    required this.duration,
    required this.reportEvery,
    required this.operationTimeout,
  });

  final String host;
  final int port;
  final String database;
  final String user;
  final String password;
  final int poolSize;
  final int concurrency;
  final Duration duration;
  final Duration reportEvery;
  final Duration operationTimeout;

  factory _SoakOptions.parse(
    List<String> arguments,
    Map<String, String> environment,
  ) {
    final values = <String, String>{};
    for (final argument in arguments) {
      final separator = argument.indexOf('=');
      if (!argument.startsWith('--') || separator < 3) {
        throw ArgumentError('Expected --name=value, received: $argument');
      }
      values[argument.substring(2, separator)] = argument.substring(separator + 1);
    }

    String value(String argument, String environmentName, String fallback) =>
        values[argument] ?? environment[environmentName] ?? fallback;
    int positiveInt(String argument, String environmentName, int fallback) {
      final parsed = int.parse(value(argument, environmentName, '$fallback'));
      if (parsed <= 0) {
        throw ArgumentError.value(parsed, argument, 'Must be greater than zero.');
      }
      return parsed;
    }

    return _SoakOptions(
      host: value('host', 'PGHOST', 'localhost'),
      port: positiveInt('port', 'PGPORT', 5432),
      database: value('database', 'PGDATABASE', 'postgres'),
      user: value('user', 'PGUSER', 'dart'),
      password: value('password', 'PGPASSWORD', 'dart'),
      poolSize: positiveInt('pool-size', 'DARGRES_SOAK_POOL_SIZE', 4),
      concurrency: positiveInt('concurrency', 'DARGRES_SOAK_CONCURRENCY', 16),
      duration: Duration(
        seconds: positiveInt('duration-seconds', 'DARGRES_SOAK_SECONDS', 60),
      ),
      reportEvery: Duration(
        seconds: positiveInt(
          'report-seconds',
          'DARGRES_SOAK_REPORT_SECONDS',
          10,
        ),
      ),
      operationTimeout: Duration(
        seconds: positiveInt('timeout-seconds', 'PGQUERY_TIMEOUT', 30),
      ),
    );
  }
}
