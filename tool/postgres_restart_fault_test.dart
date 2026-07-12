import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';

const _defaultGsudo = r'C:\gsudo\2.6.1\gsudo.exe';
const _defaultService = 'postgresql-x64-17';

Future<void> main() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('The service restart fault test requires Windows.');
  }

  final environment = Platform.environment;
  final gsudo = environment['DARGRES_GSUDO'] ?? _defaultGsudo;
  final service = environment['DARGRES_POSTGRES_SERVICE'] ?? _defaultService;
  if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(service)) {
    throw ArgumentError.value(service, 'DARGRES_POSTGRES_SERVICE');
  }
  if (!await File(gsudo).exists()) {
    throw FileSystemException('gsudo executable not found', gsudo);
  }

  final settings = ConnectionSettings(
    user: environment['PGUSER'] ?? 'dart',
    password: environment['PGPASSWORD'] ?? 'dart',
    database: environment['PGDATABASE'] ?? 'postgres',
    host: environment['PGHOST'] ?? 'localhost',
    port: int.tryParse(environment['PGPORT'] ?? '') ?? 5432,
    connectionTimeout: const Duration(seconds: 2),
    commandTimeout: const Duration(seconds: 20),
    cancelGracePeriod: const Duration(seconds: 2),
    tcpKeepalive: true,
    allowAttemptToReconnect: true,
    reconnectPolicy: const ReconnectPolicy(
      maxAttempts: 30,
      initialDelay: Duration(milliseconds: 100),
      maxDelay: Duration(seconds: 1),
      jitterFactor: 0.2,
    ),
  );

  final direct = CoreConnection.fromSettings(settings);
  final pool = PostgreSqlPool(
    2,
    settings,
    allowAttemptToReconnect: true,
    timeout: const Duration(seconds: 20),
    maxPendingOperations: 64,
  );

  try {
    await direct.connect();
    final directPidBefore = await _directPid(direct);
    final poolPidsBefore = await _poolPids(pool);
    stdout.writeln(
      'Before restart: direct=$directPidBefore pool=$poolPidsBefore',
    );

    final interrupted = <Future<Object?>>[
      _observe(direct.queryMaps('SELECT pg_sleep(30)')),
      _observe(pool.queryMaps('SELECT pg_sleep(30)')),
      _observe(pool.queryMaps('SELECT pg_sleep(30)')),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final restart = _restartPostgres(gsudo, service);
    final failures = await Future.wait(interrupted);
    if (failures.any((result) => result == null)) {
      throw StateError(
        'A 30-second command completed normally while PostgreSQL restarted: '
        '$failures',
      );
    }
    stdout.writeln(
      'Interrupted commands failed as expected: '
      '${failures.map((error) => error.runtimeType).toList()}',
    );

    // Start recovery while the service is deliberately still stopped. This
    // exercises bounded backoff instead of waiting until PostgreSQL is ready.
    final directRecovery = _directPid(direct);
    final poolRecovery = _poolPids(pool);
    await restart;
    final directPidAfter = await directRecovery;
    final poolPidsAfter = await poolRecovery;
    if (directPidAfter == directPidBefore) {
      throw StateError('Direct connection reused its pre-restart backend PID.');
    }
    if (poolPidsAfter.any(poolPidsBefore.contains)) {
      throw StateError(
        'Pool reused a pre-restart backend: before=$poolPidsBefore '
        'after=$poolPidsAfter',
      );
    }

    await Future.wait(List<Future<void>>.generate(16, (worker) async {
      for (var operation = 0; operation < 20; operation++) {
        final value = worker * 20 + operation;
        final rows = await pool.queryMaps(
          'SELECT $value::int4 AS value',
          requireBinaryResults: true,
        );
        if (rows.single['value'] != value) {
          throw StateError('Post-restart checksum mismatch at $value.');
        }
      }
    }));

    if (pool.openConnectionCount != pool.size ||
        pool.leasedConnectionCount != 0 ||
        pool.pendingOperationCount != 0) {
      throw StateError(
        'Pool invariant failed after recovery: '
        'open=${pool.openConnectionCount}/${pool.size} '
        'leased=${pool.leasedConnectionCount} '
        'pending=${pool.pendingOperationCount}',
      );
    }

    stdout.writeln(
      'Restart recovery passed: direct=$directPidAfter pool=$poolPidsAfter '
      'replacements=${pool.connectionReplacementCount} '
      'open=${pool.openConnectionCount}/${pool.size}',
    );
  } finally {
    await Future.wait<void>(<Future<void>>[direct.close(), pool.close()]);
  }
}

Future<int> _directPid(CoreConnection connection) async {
  final rows = await connection.queryMaps(
    'SELECT pg_backend_pid()::int4 AS pid',
    requireBinaryResults: true,
  );
  return rows.single['pid'] as int;
}

Future<List<int>> _poolPids(PostgreSqlPool pool) async {
  final results = await Future.wait(List.generate(2, (_) {
    return pool.queryMaps(
      'SELECT pg_backend_pid()::int4 AS pid, pg_sleep(0.15)',
    );
  }));
  final pids = results.map((rows) => rows.single['pid'] as int).toSet().toList()
    ..sort();
  if (pids.length != pool.size) {
    throw StateError('Expected ${pool.size} distinct pool PIDs, got $pids.');
  }
  return pids;
}

Future<Object?> _observe(Future<Object?> operation) async {
  try {
    await operation;
    return null;
  } catch (error) {
    return error;
  }
}

Future<void> _restartPostgres(String gsudo, String service) async {
  stdout.writeln('Restarting Windows service $service with $gsudo ...');
  final command =
      "Stop-Service -Name '$service' -Force -ErrorAction Stop; "
      'Start-Sleep -Seconds 3; '
      "Start-Service -Name '$service' -ErrorAction Stop; "
      "(Get-Service -Name '$service').WaitForStatus(" 
      "[System.ServiceProcess.ServiceControllerStatus]::Running, "
      "[TimeSpan]::FromSeconds(60))";
  final result = await Process.run(
    gsudo,
    <String>[
      'powershell.exe',
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ],
    runInShell: false,
  );
  if (result.stdout.toString().trim().isNotEmpty) {
    stdout.write(result.stdout);
  }
  if (result.stderr.toString().trim().isNotEmpty) {
    stderr.write(result.stderr);
  }
  if (result.exitCode != 0) {
    throw ProcessException(
      gsudo,
      <String>['powershell.exe', '-Command', command],
      'PostgreSQL service restart failed.',
      result.exitCode,
    );
  }
}
