import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings() => ConnectionSettings(
      user: _environment('PGUSER', 'dart'),
      database: _environment('PGDATABASE', 'postgres'),
      host: _environment('PGHOST', 'localhost'),
      port: int.parse(_environment('PGPORT', '5432')),
      password: _environment('PGPASSWORD', 'dart'),
    );

void main() {
  group('transaction commands after awaiting other I/O', () {
    // TransactionContext.execute (BEGIN/COMMIT/SAVEPOINT...) used to rely on a
    // send-loop wake-up left by the previous command; after real I/O that
    // wake-up was gone and the command waited forever.
    test('COMMIT after a timer inside the transaction', () async {
      final connection = CoreConnection.fromSettings(_settings());
      addTearDown(connection.close);
      await connection.connect();

      final result = await connection.runInTransaction((tx) async {
        await tx.queryNamed('SELECT 1', const <Object?>[]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tx.execute('SAVEPOINT depois_da_espera');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return 'ok';
      }).timeout(const Duration(seconds: 10));

      expect(result, 'ok');
    });

    test('COMMIT after a query on another connection', () async {
      final first = CoreConnection.fromSettings(_settings());
      final second = CoreConnection.fromSettings(_settings());
      addTearDown(first.close);
      addTearDown(second.close);
      await first.connect();
      await second.connect();

      final result = await first.runInTransaction((tx) async {
        await tx.queryNamed('SELECT 1', const <Object?>[]);
        await second.queryNamed('SELECT 2', const <Object?>[]);
        return 'ok';
      }).timeout(const Duration(seconds: 10));

      expect(result, 'ok');
    });

    test('a pool transaction can use another pooled connection', () async {
      final pool = PostgreSqlPool(2, _settings());
      addTearDown(pool.close);

      final pids = await pool.runInTransaction((outer) async {
        final outerPid =
            (await outer.queryNamed('SELECT pg_backend_pid()', const []))
                .first
                .first;
        final innerPid = await pool.runInTransaction((inner) async =>
            (await inner.queryNamed('SELECT pg_backend_pid()', const []))
                .first
                .first);
        return <Object?>[outerPid, innerPid];
      }, timeout: const Duration(seconds: 10));

      expect(pids[0], isNot(pids[1]));
    });
  });
}
