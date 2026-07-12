import 'dart:io';

import 'package:dargres/src/core.dart';
import 'package:dargres/src/exceptions.dart';
import 'package:test/test.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

CoreConnection _connection({String? password}) {
  return CoreConnection(
    _environment('PGUSER', 'dart'),
    database: _environment('PGDATABASE', 'postgres'),
    host: _environment('PGHOST', 'localhost'),
    port: int.parse(_environment('PGPORT', '5432')),
    password: password ?? _environment('PGPASSWORD', 'dart'),
  );
}

String _connectionUri({String? password}) {
  return Uri(
    scheme: 'postgres',
    userInfo:
        '${_environment('PGUSER', 'dart')}:${password ?? _environment('PGPASSWORD', 'dart')}',
    host: _environment('PGHOST', 'localhost'),
    port: int.parse(_environment('PGPORT', '5432')),
    path: '/${_environment('PGDATABASE', 'postgres')}',
  ).toString();
}

void main() {
  group('Connection integration', () {
    test('connects from URI and executes a query', () async {
      final connection = CoreConnection.fromUri(_connectionUri());
      addTearDown(connection.close);

      await connection.connect();

      expect(await connection.execute('select 1'), 1);
    });

    test('connects from explicit settings and executes a query', () async {
      final connection = _connection();
      addTearDown(connection.close);

      await connection.connect();

      expect(await connection.execute('select 1'), 1);
    });

    test('explicit health check performs a round trip without a background timer',
        () async {
      final connection = _connection();
      addTearDown(connection.close);

      expect(await connection.checkHealth(), isFalse);
      await connection.connect();
      await connection.ping();
      expect(await connection.checkHealth(), isTrue);

      await connection.close();
      expect(await connection.checkHealth(), isFalse);
      await expectLater(
        connection.ping(),
        throwsA(isA<PostgresqlException>()),
      );
    });

    test('rejects an invalid password', () async {
      final configuredPassword = _environment('PGPASSWORD', 'dart');
      final connection = _connection(password: '${configuredPassword}_invalid');
      addTearDown(connection.close);

      await expectLater(
        connection.connect(),
        throwsA(isA<PostgresqlException>()),
      );
    });

    test('reports a missing SCRAM password without an internal null error',
        () async {
      final connection = CoreConnection(
        _environment('PGUSER', 'dart'),
        database: _environment('PGDATABASE', 'postgres'),
        host: _environment('PGHOST', 'localhost'),
        port: int.parse(_environment('PGPORT', '5432')),
      );
      addTearDown(connection.close);

      await expectLater(
        connection.connect(),
        throwsA(
          isA<PostgresqlException>().having(
            (error) => error.message,
            'message',
            contains('no password was provided'),
          ),
        ),
      );
    });

    test('supports independent concurrent connections', () async {
      final first = _connection();
      final second = _connection();
      addTearDown(() async {
        await Future.wait([first.close(), second.close()]);
      });

      await Future.wait([first.connect(), second.connect()]);

      expect(
        await Future.wait([
          first.execute('select 1'),
          second.execute('select 1'),
        ]),
        [1, 1],
      );
    });

    test('SCRAM startup remains stable under repeated concurrent churn',
        () async {
      for (var batch = 0; batch < 5; batch++) {
        final connections = List<CoreConnection>.generate(
          8,
          (_) => _connection(),
          growable: false,
        );
        try {
          await Future.wait(connections.map((connection) => connection.connect()));
          expect(
            await Future.wait(
              connections.map((connection) => connection.execute('select 1')),
            ),
            List<int>.filled(connections.length, 1, growable: false),
          );
        } finally {
          await Future.wait(
            connections.map((connection) => connection.close()),
          );
        }
      }
    });

    test('long-lived connection serializes hundreds of queued writes',
        () async {
      final connection = _connection();
      addTearDown(connection.close);
      await connection.connect();

      final operations = List<Future<List<Map<String, dynamic>>>>.generate(
        250,
        (value) => connection.queryMaps(
          r'SELECT $1::int4 AS value',
          params: <Object?>[value],
        ),
        growable: false,
      );
      final results = await Future.wait(operations);

      for (var value = 0; value < results.length; value++) {
        expect(results[value].single['value'], value);
      }
    });

    test('strict binary rejects unsupported OIDs without retrying side effects',
        () async {
      final connection = _connection();
      addTearDown(connection.close);
      await connection.connect();
      await connection.execute(
        'CREATE TEMPORARY SEQUENCE dargres_strict_binary_sequence',
      );

      await expectLater(
        connection.queryMaps(
          "SELECT nextval('dargres_strict_binary_sequence')::numeric AS value",
          requireBinaryResults: true,
        ),
        throwsA(isA<UnsupportedError>()),
      );

      final next = await connection.queryMaps(
        "SELECT nextval('dargres_strict_binary_sequence')::int8 AS value",
        requireBinaryResults: true,
      );
      expect(next.single['value'], 2,
          reason: 'The rejected statement must have executed exactly once.');
    });
  });
}
