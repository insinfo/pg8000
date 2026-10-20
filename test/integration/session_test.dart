import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:dargres/src/connection_state.dart';
import 'package:test/test.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

const _searchPath = '"pg_catalog","public"';

ConnectionSettings _settings({
  String? searchPath = _searchPath,
  List<String> sessionStatements = const <String>[],
  bool allowAttemptToReconnect = false,
}) =>
    ConnectionSettings(
      user: _environment('PGUSER', 'dart'),
      database: _environment('PGDATABASE', 'postgres'),
      host: _environment('PGHOST', 'localhost'),
      port: int.parse(_environment('PGPORT', '5432')),
      password: _environment('PGPASSWORD', 'dart'),
      allowAttemptToReconnect: allowAttemptToReconnect,
      timeZone: const TimeZoneSettings('America/Sao_Paulo'),
      searchPath: searchPath,
      sessionStatements: sessionStatements,
    );

Future<String> _show(dynamic connection, String name) async {
  final rows = await connection.queryNamed('SHOW $name', const <Object?>[]);
  return rows.first.first as String;
}

void main() {
  group('session initialization', () {
    test('applies search_path, statements, encoding and DateStyle', () async {
      final connection = CoreConnection.fromSettings(_settings(
          sessionStatements: const <String>["SET statement_timeout = '45s'"]));
      addTearDown(connection.close);
      await connection.connect();

      expect(await _show(connection, 'search_path'), 'pg_catalog, public');
      expect(await _show(connection, 'statement_timeout'), '45s');
      expect(await _show(connection, 'client_encoding'), 'UTF8');
      expect(await _show(connection, 'DateStyle'), startsWith('ISO'));
      expect(await _show(connection, 'TimeZone'), 'America/Sao_Paulo');
    });

    test('queries queued before connect completes see the session', () async {
      final connection = CoreConnection.fromSettings(_settings());
      addTearDown(connection.close);

      final connecting = connection.connect();
      final pending = _show(connection, 'search_path');
      await connecting;

      expect(await pending, 'pg_catalog, public');
    });

    test('a transaction queued while connecting starts after the session',
        () async {
      final connection = CoreConnection.fromSettings(_settings());
      addTearDown(connection.close);

      final connecting = connection.connect();
      final path = connection.runInTransaction((tx) async {
        final rows =
            await tx.queryNamed('SHOW search_path', const <Object?>[]);
        return rows.first.first as String;
      });
      await connecting;

      expect(await path.timeout(const Duration(seconds: 10)),
          'pg_catalog, public');
    });

    test('every pooled physical connection is initialized', () async {
      final pool = PostgreSqlPool(2, _settings());
      addTearDown(pool.close);

      final paths = await Future.wait(List.generate(
          4,
          (_) => pool.runInTransaction((tx) async {
                final rows = await tx.queryNamed(
                    'SELECT current_setting(?), pg_backend_pid()',
                    <Object?>['search_path'],
                    placeholderIdentifier:
                        PlaceholderIdentifier.onlyQuestionMark);
                return rows.first.first as String;
              })));

      expect(paths, everyElement('pg_catalog, public'));
      expect(pool.openConnectionCount, 2);
    });

    test('a failing statement fails connect and closes the socket', () async {
      final connection = CoreConnection.fromSettings(_settings(
          sessionStatements: const <String>['SET dargres_nao_existe = 1']));
      addTearDown(connection.close);

      await expectLater(
          connection.connect(),
          throwsA(isA<PostgresqlException>().having((e) => e.message,
              'message', contains('session initialization failed'))));
      expect(connection.connectionState, ConnectionState.closed);
    });

    test('a reconnected session is initialized again', () async {
      final connection =
          CoreConnection.fromSettings(_settings(allowAttemptToReconnect: true));
      final killer = CoreConnection.fromSettings(_settings(searchPath: null));
      addTearDown(connection.close);
      addTearDown(killer.close);
      await connection.connect();
      await killer.connect();

      final pid = connection.backendPid;
      await killer.queryNamed('SELECT pg_terminate_backend(?::int)',
          <Object?>[pid],
          placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
      // Let the socket observe the server-side termination.
      for (var i = 0;
          i < 50 && connection.connectionState != ConnectionState.closed;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      await connection.tryReconnect();
      expect(connection.backendPid, isNot(pid));
      expect(await _show(connection, 'search_path'), 'pg_catalog, public');
    });
  });

  group('text and binary date results agree', () {
    test('cold (text) and warm (binary) executions decode the same', () async {
      final connection = CoreConnection.fromSettings(_settings());
      addTearDown(connection.close);
      await connection.connect();

      const sql = "SELECT '2018-11-04 00:00:00'::timestamp dst_start, "
          "'0001-01-01 BC'::date bc, "
          "'1900-01-01 00:00:00'::timestamptz lmt, "
          "'2026-10-19 14:30:15.123456'::timestamp micro";
      final cold = (await connection.queryNamed(sql, const <Object?>[])).first;
      final warm = (await connection.queryNamed(sql, const <Object?>[])).first;

      expect(cold.toList(), warm.toList());
      expect(cold[0], DateTime.utc(2018, 11, 4));
      expect(cold[1], DateTime.utc(0));
      expect(cold[2], DateTime.utc(1900, 1, 1, 3, 6, 28));
      expect(cold[3], DateTime.utc(2026, 10, 19, 14, 30, 15, 0, 123456));
    });
  });
}
