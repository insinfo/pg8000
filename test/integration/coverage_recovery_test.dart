// Errors and recovery against a real server: cancelCurrentQuery and
// commandTimeout through every protocol path, a backend terminated from
// another connection (with and without allowAttemptToReconnect), callers
// queued when the connection dies (they must fail, never hang), and errors
// inside runInTransaction while callers outside wait for it.

import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:dargres/src/connection_state.dart';
import 'package:dargres/src/transaction_state.dart';
import 'package:test/test.dart';

String _env(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings({
  Duration? commandTimeout,
  bool allowAttemptToReconnect = false,
  List<String> sessionStatements = const [],
}) =>
    ConnectionSettings(
      user: _env('PGUSER', 'dart'),
      database: _env('PGDATABASE', 'postgres'),
      host: _env('PGHOST', 'localhost'),
      port: int.parse(_env('PGPORT', '5432')),
      password: _env('PGPASSWORD', 'dart'),
      commandTimeout: commandTimeout,
      cancelGracePeriod: const Duration(seconds: 1),
      allowAttemptToReconnect: allowAttemptToReconnect,
      reconnectPolicy: const ReconnectPolicy(
          maxAttempts: 3, initialDelay: Duration(milliseconds: 10)),
      sessionStatements: sessionStatements,
    );

/// Never hang: every call in these tests resolves well before this.
const _deadline = Duration(seconds: 15);

Future<CoreConnection> _open({
  Duration? commandTimeout,
  bool allowAttemptToReconnect = false,
  List<String> sessionStatements = const [],
}) async {
  final connection = CoreConnection.fromSettings(_settings(
      commandTimeout: commandTimeout,
      allowAttemptToReconnect: allowAttemptToReconnect,
      sessionStatements: sessionStatements));
  await connection.connect();
  addTearDown(connection.close);
  return connection;
}

Matcher _sqlState(String code) => isA<PostgresqlException>()
    .having((e) => e.serverErrorCode, 'SQLSTATE', code);

Future<int> _one(CoreConnection c, [int n = 1]) async =>
    (await c.queryNamed('select \$1::int4', [n]).timeout(_deadline)).single[0]
        as int;

/// Waits until the server-side session of [c] runs [sql] (a sleep).
Future<void> _waitUntilRunning(CoreConnection admin, int pid) async {
  for (var i = 0; i < 200; i++) {
    final rows = await admin.queryUnnamed(
        "select 1 from pg_stat_activity where pid = \$1::int4 "
        "and state = 'active' and wait_event = 'PgSleep'",
        [pid]);
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('backend $pid never started sleeping');
}

Future<void> _terminate(CoreConnection admin, int pid) async {
  final rows =
      await admin.queryUnnamed(r'select pg_terminate_backend($1::int4)', [pid]);
  expect(rows.single[0], isTrue);
}

Future<void> _waitClosed(CoreConnection c) async {
  for (var i = 0; i < 250 && c.connectionState != ConnectionState.closed; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(c.connectionState, ConnectionState.closed);
}

/// The long-running command of every protocol path.
final _sleepers = <String, Future<Object?> Function(CoreConnection c)>{
  'execute': (c) => c.execute('select pg_sleep(30)'),
  'querySimple multi-statement': (c) =>
      c.querySimple('select 1; select pg_sleep(30); select 2'),
  'querySimpleAsStream': (c) async =>
      (await c.querySimpleAsStream('select pg_sleep(30)')).toList(),
  'queryNamed': (c) => c.queryNamed(r'select pg_sleep($1)', [30]),
  'queryUnnamed': (c) => c.queryUnnamed(r'select pg_sleep($1)', [30]),
  'queryMaps': (c) => c.queryMaps('select pg_sleep(30)'),
  'queryMaps binary': (c) => c.queryMaps('select 1::int4 from pg_sleep(30)',
      requireBinaryResults: true),
  'prepareStatement + executeStatement': (c) async => c
      .executeStatement(await c.prepareStatement(r'select pg_sleep($1)', [30])),
  'rows then a sleep': (c) => c.queryNamed(
      'select g, pg_sleep(case when g = 3 then 30 else 0 end) '
      'from generate_series(1, 3) g',
      const []),
};

class _Rollback implements Exception {}

/// Listens to every call at once (a failure without a listener is reported
/// as an uncaught error) and expects each to fail.
Future<void> _allFail(List<Future<Object?>> calls) => Future.wait([
      for (final call in calls)
        expectLater(call.timeout(_deadline), throwsA(anything)),
    ]);

void main() {
  late CoreConnection admin;
  setUpAll(() async {
    admin = CoreConnection.fromSettings(_settings());
    await admin.connect();
    await admin.execute('drop table if exists cov_r; '
        'create table cov_r (id serial primary key, name text unique)');
  });
  tearDownAll(() async {
    await admin.execute('drop table if exists cov_r');
    await admin.close();
  });
  setUp(() => admin.execute('truncate cov_r restart identity'));

  Future<List<String>> names() async => [
        for (final row in await admin
            .queryUnnamed('select name from cov_r order by id', const []))
          row[0] as String
      ];

  group('cancelCurrentQuery', () {
    test('returns false while idle', () async {
      final c = await _open();
      expect(await c.cancelCurrentQuery(), isFalse);
      expect(await _one(c), 1);
    });

    for (final entry in _sleepers.entries) {
      test(entry.key, () async {
        final c = await _open();
        final sleeping = entry.value(c);
        // Queued behind the sleeper: must run, with its own result.
        final queued = [_one(c, 2), _one(c, 3)];
        await _waitUntilRunning(admin, c.backendPid);
        expect(await c.cancelCurrentQuery(), isTrue);
        await expectLater(
            sleeping.timeout(_deadline), throwsA(_sqlState('57014')));
        expect(await Future.wait(queued), [2, 3]);
        expect(await _one(c, 4), 4);
        expect(c.transactionState, TransactionState.none);
      });
    }

    test('in a transaction: it rolls back and outside callers run after',
        () async {
      final c = await _open();
      final entered = Completer<void>();
      final transaction = c.runInTransaction((tx) async {
        await tx.execute("insert into cov_r (name) values ('tx')");
        entered.complete();
        await tx.execute('select pg_sleep(30)');
      });
      await entered.future;
      final outside = c.queryNamed(
          r'insert into cov_r (name) values ($1) returning name', ['out']);
      await _waitUntilRunning(admin, c.backendPid);
      expect(await c.cancelCurrentQuery(), isTrue);
      await expectLater(
          transaction.timeout(_deadline), throwsA(_sqlState('57014')));
      expect((await outside.timeout(_deadline)).single[0], 'out');
      expect(await names(), ['out']);
      expect(c.transactionState, TransactionState.none);
    });

    test('pg_cancel_backend from another connection', () async {
      final c = await _open();
      final sleeping = c.queryNamed('select pg_sleep(30)', const []);
      await _waitUntilRunning(admin, c.backendPid);
      await admin
          .queryUnnamed(r'select pg_cancel_backend($1::int4)', [c.backendPid]);
      await expectLater(
          sleeping.timeout(_deadline), throwsA(_sqlState('57014')));
      expect(await _one(c, 5), 5);
    });
  });

  group('commandTimeout', () {
    for (final entry in _sleepers.entries) {
      test(entry.key, () async {
        final c =
            await _open(commandTimeout: const Duration(milliseconds: 300));
        final sleeping = entry.value(c);
        final queued = _one(c, 2);
        await expectLater(
            sleeping.timeout(_deadline), throwsA(isA<TimeoutException>()));
        expect(await queued, 2);
        expect(await c.checkHealth(), isTrue);
        expect(c.connectionState, isNot(ConnectionState.closed));
      });
    }

    test('time spent waiting in the queue does not count', () async {
      final c = await _open(commandTimeout: const Duration(milliseconds: 700));
      final results = await Future.wait([
        for (var i = 0; i < 3; i++)
          c.queryNamed('select pg_sleep(0.4), $i::int4', const []),
      ]).timeout(_deadline);
      expect([for (final rows in results) rows.single[1]], [0, 1, 2]);
    });

    test('inside runInTransaction: rolled back, outside callers proceed',
        () async {
      final c = await _open(commandTimeout: const Duration(milliseconds: 300));
      final entered = Completer<void>();
      final transaction = c.runInTransaction((tx) async {
        await tx.execute("insert into cov_r (name) values ('tx')");
        entered.complete();
        await tx.queryNamed('select pg_sleep(30)', const []);
      });
      await entered.future;
      final outside = c.execute("insert into cov_r (name) values ('out')");
      await expectLater(
          transaction.timeout(_deadline), throwsA(isA<TimeoutException>()));
      expect(await outside.timeout(_deadline), 1);
      expect(await names(), ['out']);
      expect(c.transactionState, TransactionState.none);
    });

    test('a cancel the server ignores closes the connection after the grace',
        () async {
      final c = await _open(commandTimeout: const Duration(milliseconds: 200));
      // The function swallows the cancel and keeps sleeping.
      const stubborn = r"do $$ begin perform pg_sleep(30); "
          r'exception when query_canceled then perform pg_sleep(30); end $$';
      final sleeping = c.execute(stubborn);
      // Queued callers fail with the connection.
      final queued =
          _allFail([_one(c), c.execute('select 1'), c.querySimple('select 1')]);
      await expectLater(
          sleeping.timeout(_deadline), throwsA(isA<TimeoutException>()));
      await queued;
      expect(c.connectionState, ConnectionState.closed);
      await expectLater(_one(c), throwsA(isA<PostgresqlException>()));
    });

    test('a cancel the server ignores, then a reconnect', () async {
      final c = await _open(
          commandTimeout: const Duration(milliseconds: 200),
          allowAttemptToReconnect: true);
      const stubborn = r"do $$ begin perform pg_sleep(30); "
          r'exception when query_canceled then perform pg_sleep(30); end $$';
      final pid = c.backendPid;
      await expectLater(c.execute(stubborn).timeout(_deadline),
          throwsA(isA<TimeoutException>()));
      expect(await _one(c, 6), 6);
      expect(c.backendPid, isNot(pid));
    });
  });

  group('backend terminated from another connection', () {
    test('idle, without reconnect: later calls fail, never hang', () async {
      final c = await _open();
      await _terminate(admin, c.backendPid);
      await _waitClosed(c);
      await expectLater(_one(c), throwsA(isA<PostgresqlException>()));
      await expectLater(c.execute('select 1').timeout(_deadline),
          throwsA(isA<PostgresqlException>()));
      await expectLater(
          c.runInTransaction((tx) => tx.execute('select 1')).timeout(_deadline),
          throwsA(isA<PostgresqlException>()));
      expect(await c.checkHealth(), isFalse);
    });

    test('idle, with reconnect: the next call reconnects', () async {
      final c = await _open(allowAttemptToReconnect: true);
      final pid = c.backendPid;
      expect(await _one(c, 1), 1); // cached statement of the old session
      await _terminate(admin, pid);
      await _waitClosed(c);
      expect(await _one(c, 2), 2);
      expect(c.backendPid, isNot(pid));
      expect(await _one(c, 3), 3);
      expect(
          await c.runInTransaction((tx) async =>
              (await tx.queryNamed(r'select $1::int4', [4])).single[0]),
          4);
    });

    test('immediately followed by a call: it fails or reconnects, never hangs',
        () async {
      for (final reconnect in [false, true]) {
        final c = await _open(allowAttemptToReconnect: reconnect);
        await _terminate(admin, c.backendPid);
        try {
          expect(await _one(c, 7), 7);
        } on PostgresqlException {
          // The termination arrived first.
        }
        if (reconnect) {
          await _waitClosed(c).catchError((_) {});
          expect(await _one(c, 8), 8);
        }
      }
    });

    for (final reconnect in [false, true]) {
      test(
          'busy with queued callers (allowAttemptToReconnect: $reconnect): '
          'all fail', () async {
        final c = await _open(allowAttemptToReconnect: reconnect);
        final sleeping = expectLater(
            c.queryNamed('select pg_sleep(30)', const []).timeout(_deadline),
            throwsA(isA<PostgresqlException>()));
        final queued = _allFail([
          _one(c),
          c.execute('select 1'),
          c.querySimple('select 1'),
          c.queryMaps('select 1'),
          c.runInTransaction((tx) => tx.execute('select 1')),
        ]);
        await _waitUntilRunning(admin, c.backendPid);
        await _terminate(admin, c.backendPid);
        await sleeping;
        await queued;
        if (reconnect) {
          expect(await _one(c, 9), 9);
        } else {
          await expectLater(_one(c), throwsA(isA<PostgresqlException>()));
        }
      });
    }

    for (final reconnect in [false, true]) {
      test(
          'inside runInTransaction with callers outside '
          '(allowAttemptToReconnect: $reconnect)', () async {
        final c = await _open(allowAttemptToReconnect: reconnect);
        final entered = Completer<void>();
        final transaction = c.runInTransaction((tx) async {
          await tx.execute("insert into cov_r (name) values ('tx')");
          entered.complete();
          await tx.execute('select pg_sleep(30)');
        });
        await entered.future;
        final transactionFails = expectLater(transaction.timeout(_deadline),
            throwsA(isA<PostgresqlException>()));
        final outside = _allFail([
          c.execute("insert into cov_r (name) values ('out1')"),
          c.queryNamed(r'insert into cov_r (name) values ($1)', ['out2']),
        ]);
        await _waitUntilRunning(admin, c.backendPid);
        await _terminate(admin, c.backendPid);
        await transactionFails;
        await outside;
        expect(await names(), isEmpty);
        if (reconnect) expect(await _one(c, 10), 10);
      });
    }

    test(
        'the callback goes on after its transaction died: nothing runs '
        'outside the transaction on the reconnected session', () async {
      final c = await _open(allowAttemptToReconnect: true);
      final transaction = c.runInTransaction((tx) async {
        await c.execute("insert into cov_r (name) values ('a')");
        await _terminate(admin, c.backendPid);
        await _waitClosed(c);
        Object? failure;
        try {
          await c.execute("insert into cov_r (name) values ('b')");
        } catch (error) {
          failure = error;
        }
        try {
          await c.queryNamed(r'insert into cov_r (name) values ($1)', ['c']);
        } catch (error) {
          failure ??= error;
        }
        expect(failure, isNotNull);
      });
      await expectLater(transaction.timeout(_deadline), throwsA(anything));
      expect(await names(), isEmpty,
          reason: 'b and c would have been committed outside the transaction');
      expect(await _one(c, 11), 11);
    });

    test('pool replaces its terminated connection', () async {
      final pool = PostgreSqlPool(1, _settings());
      addTearDown(pool.close);
      final pid = (await pool.queryNamed('select pg_backend_pid()', const []))
          .single[0] as int;
      await _terminate(admin, pid);
      // Let the idle socket observe the termination.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final newPid =
          (await pool.queryNamed('select pg_backend_pid()', const [])).single[0]
              as int;
      expect(newPid, isNot(pid));
      expect(pool.connectionReplacementCount, 1);
    });

    test('idle_in_transaction_session_timeout ends the session', () async {
      final c = await _open(
          allowAttemptToReconnect: true,
          sessionStatements: const [
            "set idle_in_transaction_session_timeout = '200ms'"
          ]);
      final transaction = c.runInTransaction((tx) async {
        await tx.execute("insert into cov_r (name) values ('tx')");
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await tx.execute("insert into cov_r (name) values ('tx2')");
      });
      await expectLater(transaction.timeout(_deadline), throwsA(anything));
      expect(await names(), isEmpty);
      expect(await _one(c, 12), 12);
    });

    test('idle_session_timeout (57P05) then a reconnect', () async {
      final c = await _open(
          allowAttemptToReconnect: true,
          sessionStatements: const ["set idle_session_timeout = '200ms'"]);
      final pid = c.backendPid;
      await _waitClosed(c);
      expect(await _one(c, 13), 13);
      expect(c.backendPid, isNot(pid));
    });
  });

  group('close() with work in flight', () {
    test('active, queued and transaction callers fail', () async {
      final c = CoreConnection.fromSettings(_settings());
      await c.connect();
      final queued = _allFail([
        c.queryNamed('select pg_sleep(30)', const []),
        _one(c),
        c.execute('select 1'),
        c.runInTransaction((tx) => tx.execute('select 1')),
      ]);
      await _waitUntilRunning(admin, c.backendPid);
      await c.close();
      await queued;
      await expectLater(_one(c), throwsA(anything));
    });
  });

  group('errors inside runInTransaction with callers waiting outside', () {
    late CoreConnection c;
    setUp(() async => c = await _open());

    Future<void> withOutsideCallers(
        Future<void> Function(TransactionContext tx) body,
        Matcher failure) async {
      final entered = Completer<void>();
      final transaction = c.runInTransaction((tx) async {
        await tx.execute("insert into cov_r (name) values ('tx')");
        entered.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await body(tx);
      });
      await entered.future;
      final outside = Future.wait([
        c.execute("insert into cov_r (name) values ('o1')"),
        c.queryNamed(r'insert into cov_r (name) values ($1)', ['o2']),
        c.queryMaps('select count(*)::int4 as n from cov_r'),
      ]);
      await expectLater(transaction.timeout(_deadline), throwsA(failure));
      final results = await outside.timeout(_deadline);
      expect((results[2] as List).single, {'n': 2});
      expect(await names(), ['o1', 'o2']);
      expect(c.transactionState, TransactionState.none);
    }

    test('the callback throws', () async {
      await withOutsideCallers(
          (tx) async => throw _Rollback(), isA<_Rollback>());
    });

    test('a statement fails', () async {
      await withOutsideCallers(
          (tx) => tx.execute("insert into cov_r (name) values ('tx')"),
          _sqlState('23505'));
    });

    test('a statement fails and the callback keeps using the transaction',
        () async {
      await withOutsideCallers((tx) async {
        try {
          await tx.queryNamed('select 1 / 0', const []);
        } on PostgresqlException {
          // Ignored: the transaction is aborted anyway.
        }
        await tx.queryNamed('select 1', const []);
      }, _sqlState('25P02'));
    });

    test('COMMIT fails (deferred constraint)', () async {
      await c.execute('drop table if exists cov_r2; create table cov_r2 '
          '(v int4 unique deferrable initially deferred)');
      addTearDown(() => c.execute('drop table if exists cov_r2'));
      await withOutsideCallers((tx) async {
        await tx.execute('insert into cov_r2 values (1), (1)');
      }, _sqlState('23505'));
    });

    test('an uncaught error in a zone-routed query', () async {
      await withOutsideCallers(
          (tx) => c.queryNamed('select 1 / 0', const []), _sqlState('22012'));
    });
  });
}
