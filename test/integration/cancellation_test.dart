import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings({Duration? commandTimeout}) =>
    ConnectionSettings(
      user: _environment('PGUSER', 'dart'),
      password: _environment('PGPASSWORD', 'dart'),
      database: _environment('PGDATABASE', 'postgres'),
      host: _environment('PGHOST', 'localhost'),
      port: int.parse(_environment('PGPORT', '5432')),
      commandTimeout: commandTimeout,
      cancelGracePeriod: const Duration(seconds: 2),
    );

void main() {
  group('PostgreSQL command cancellation', () {
    test('command timeout cancels on the server and preserves the connection',
        () async {
      final connection = CoreConnection.fromSettings(
        _settings(commandTimeout: const Duration(milliseconds: 150)),
      );
      await connection.connect();
      addTearDown(connection.close);

      final elapsed = Stopwatch()..start();
      await expectLater(
        connection.queryMaps('SELECT pg_sleep(10)'),
        throwsA(isA<TimeoutException>()),
      );
      elapsed.stop();

      expect(elapsed.elapsed, lessThan(const Duration(seconds: 3)));
      final rows = await connection.queryMaps('SELECT 42::int4 AS value');
      expect(rows.single['value'], 42);
      expect(await connection.checkHealth(), isTrue);
    });

    test('manual CancelRequest cancels only the active command', () async {
      final connection = CoreConnection.fromSettings(
        _settings(commandTimeout: const Duration(seconds: 30)),
      );
      await connection.connect();
      addTearDown(connection.close);

      final query = connection.queryMaps('SELECT pg_sleep(10)');
      final cancelled = expectLater(
        query,
        throwsA(
          isA<PostgresqlException>()
              .having((error) => error.serverErrorCode, 'SQLSTATE', '57014'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(await connection.cancelCurrentQuery(), isTrue);
      await cancelled;
      expect(await connection.cancelCurrentQuery(), isFalse);

      final rows = await connection.queryMaps('SELECT 7::int4 AS value');
      expect(rows.single['value'], 7);
    });
  });
}
