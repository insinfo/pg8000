// Every entry point of CoreConnection, TransactionContext and PostgreSqlPool
// against every kind of statement (rows, no rows, DML with and without
// RETURNING, DDL, SET, NOTICE, multi-statement, errors, errors after rows,
// COPY). After each call the next command on the same connection must get
// its own result: a response left behind by one statement (NoData, a NOTICE,
// an error after rows, COPY messages) used to be the classic desync.
//
// Each statement runs twice: cold (Parse+Describe+Bind+Execute, text) and
// warm (cache hit: Bind+Execute, selective binary).

import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:dargres/src/server_notice.dart';
import 'package:dargres/src/transaction_state.dart';
import 'package:test/test.dart';

String _env(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings() => ConnectionSettings(
      user: _env('PGUSER', 'dart'),
      database: _env('PGDATABASE', 'postgres'),
      host: _env('PGHOST', 'localhost'),
      port: int.parse(_env('PGPORT', '5432')),
      password: _env('PGPASSWORD', 'dart'),
      commandTimeout: const Duration(seconds: 10),
    );

const _callTimeout = Duration(seconds: 8);

const _reset = 'drop table if exists cov_m_tmp; '
    'truncate cov_m restart identity; '
    'insert into cov_m (v) values (1), (2), (3)';

/// What one call returned, normalized across the entry points.
class _Outcome {
  _Outcome(this.rows, this.affected);

  /// Null for entry points that do not return rows (`execute`).
  final List<List<Object?>>? rows;

  /// Null for entry points that do not report it (`queryMaps`, ...).
  final int? affected;
}

enum _Protocol { simple, extended }

/// [sql] has `{p}` where the one parameter goes (inlined for the simple
/// protocol, a placeholder for the extended one).
class _Kind {
  const _Kind(
    this.name,
    this.sql, {
    this.param,
    this.rows = const [],
    this.affected = 0,
    this.sqlState,
    this.extendedSqlState,
    this.sortRows = false,
    this.notice,
    this.writes = false,
  });

  final String name;
  final String sql;
  final Object? param;
  final List<List<Object?>> rows;
  final int affected;

  /// Expected SQLSTATE when the statement fails.
  final String? sqlState;

  /// Expected SQLSTATE on the extended protocol when it differs.
  final String? extendedSqlState;
  final bool sortRows;

  /// Text that a NOTICE raised by the statement contains.
  final String? notice;

  /// Changes cov_m or creates a table: left out of the pipelined bursts,
  /// where the other writers would change its result.
  final bool writes;

  String? failure(_Protocol protocol) =>
      protocol == _Protocol.extended ? extendedSqlState ?? sqlState : sqlState;
}

const _kinds = <_Kind>[
  _Kind(
      'select rows', 'select g::int4 as g from generate_series(1, {p}::int4) g',
      param: 3,
      rows: [
        [1],
        [2],
        [3]
      ],
      affected: 3),
  _Kind('select 0 rows', 'select 1::int4 as x where {p}::int4 = 0',
      param: 1, affected: 0),
  _Kind('insert',
      'insert into cov_m (v) select g from generate_series(1, {p}::int4) g',
      param: 2, affected: 2, writes: true),
  _Kind('insert returning',
      'insert into cov_m (v) values ({p}::int4) returning v',
      param: 7,
      rows: [
        [7]
      ],
      affected: 1,
      writes: true),
  _Kind('update', 'update cov_m set v = v where v <= {p}::int4',
      param: 2, affected: 2, writes: true),
  _Kind('update returning',
      'update cov_m set v = v * 10 where v = {p}::int4 returning v',
      param: 3,
      rows: [
        [30]
      ],
      affected: 1,
      writes: true),
  _Kind('update 0 rows', 'update cov_m set v = v where v = {p}::int4',
      param: 99, affected: 0),
  _Kind('delete', 'delete from cov_m where v = {p}::int4',
      param: 1, affected: 1, writes: true),
  _Kind(
      'delete returning', 'delete from cov_m where v >= {p}::int4 returning v',
      param: 2,
      rows: [
        [2],
        [3]
      ],
      affected: 2,
      sortRows: true,
      writes: true),
  _Kind('ddl', 'create table cov_m_tmp (id int4)', writes: true),
  _Kind('set', "set application_name = 'cov_matrix'"),
  _Kind(
      'do with raise notice', r"do $$ begin raise notice 'cov notice'; end $$",
      notice: 'cov notice'),
  _Kind('drop if exists (notice)', 'drop table if exists cov_m_missing',
      notice: 'cov_m_missing'),
  _Kind('rows with a notice per row',
      'select cov_notify(g)::int4 as g from generate_series(1, {p}::int4) g',
      param: 2,
      rows: [
        [1],
        [2]
      ],
      affected: 2,
      notice: 'cov row'),
  _Kind('comment only', '-- nothing to run'),
  _Kind('multi-statement', 'select 1::int4 as a; select 2::int4 as b',
      rows: [
        [1],
        [2]
      ],
      affected: 1,
      extendedSqlState: '42601'),
  _Kind('multi-statement with an error in the middle',
      'select 1::int4; select 1 / 0; select 3::int4',
      sqlState: '22012', extendedSqlState: '42601'),
  _Kind('error', 'select 1 / {p}::int4', param: 0, sqlState: '22012'),
  _Kind('error after rows',
      'select (10 / (3 - g))::int4 as v from generate_series(1, {p}::int4) g',
      param: 5, sqlState: '22012'),
  _Kind('syntax error', 'selec 1', sqlState: '42601'),
  _Kind('unique violation', 'insert into cov_m (id, v) values ({p}::int4, 0)',
      param: 1, sqlState: '23505'),
  _Kind('raise exception with errcode',
      r"do $$ begin raise exception 'cov boom' using errcode = 'CV001'; end $$",
      sqlState: 'CV001'),
  _Kind('copy to stdout',
      'copy (select g from generate_series(1, 3) g) to stdout',
      affected: 3),
  _Kind('copy from stdin', 'copy cov_m (v) from stdin', sqlState: '57014'),
];

String _inline(String sql, Object? param) => sql.replaceAll('{p}', '$param');

String _with(String sql, String placeholder) =>
    sql.replaceAll('{p}', placeholder);

List<Object?> _list(_Kind k) => k.sql.contains('{p}') ? [k.param] : [];

Map<String, Object?> _map(_Kind k) =>
    k.sql.contains('{p}') ? {'p': k.param} : {};

_Outcome _results(Results results) => _Outcome(
    [for (final row in results) row.toList()], results.rowsAffected.value);

/// One entry point; [run] receives a CoreConnection, a TransactionContext or a
/// PostgreSqlPool (they share the method names), hence `dynamic`.
class _Api {
  const _Api(this.name, this.protocol, this.run, {this.pool = true});

  final String name;
  final _Protocol protocol;
  final Future<_Outcome> Function(dynamic ctx, _Kind kind) run;

  /// Whether PostgreSqlPool has this entry point.
  final bool pool;
}

final _apis = <_Api>[
  _Api(
      'execute',
      _Protocol.simple,
      (ctx, k) async =>
          _Outcome(null, await ctx.execute(_inline(k.sql, k.param)))),
  _Api(
      'querySimple',
      _Protocol.simple,
      (ctx, k) async =>
          _results(await ctx.querySimple(_inline(k.sql, k.param)))),
  _Api('querySimpleAsStream', _Protocol.simple, (ctx, k) async {
    final ResultStream stream =
        await ctx.querySimpleAsStream(_inline(k.sql, k.param));
    final rows = await stream.toList();
    return _Outcome(
        [for (final row in rows) row.toList()], stream.rowsAffected.value);
  }, pool: false),
  _Api(
      r'queryUnnamed $1',
      _Protocol.extended,
      (ctx, k) async =>
          _results(await ctx.queryUnnamed(_with(k.sql, r'$1'), _list(k)))),
  _Api(
      'queryUnnamed ?',
      _Protocol.extended,
      (ctx, k) async => _results(await ctx.queryUnnamed(
          _with(k.sql, '?'), _list(k),
          placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark))),
  _Api(
      r'queryNamed $1',
      _Protocol.extended,
      (ctx, k) async =>
          _results(await ctx.queryNamed(_with(k.sql, r'$1'), _list(k)))),
  _Api(
      'queryNamed ?',
      _Protocol.extended,
      (ctx, k) async => _results(await ctx.queryNamed(
          _with(k.sql, '?'), _list(k),
          placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark))),
  _Api(
      'queryNamed :name',
      _Protocol.extended,
      (ctx, k) async => _results(await ctx.queryNamed(
          _with(k.sql, ':p'), _map(k),
          placeholderIdentifier: PlaceholderIdentifier.colon))),
  _Api(
      'queryNamed @name',
      _Protocol.extended,
      (ctx, k) async => _results(await ctx.queryNamed(
          _with(k.sql, '@p'), _map(k),
          placeholderIdentifier: PlaceholderIdentifier.atSign))),
  _Api(
      'queryNamed isDeallocate',
      _Protocol.extended,
      (ctx, k) async => _results(await ctx
          .queryNamed(_with(k.sql, r'$1'), _list(k), isDeallocate: true))),
  _Api(
      'queryCached',
      _Protocol.extended,
      (ctx, k) async => _results(
          await ctx.queryCached(_with(k.sql, r'$1'), params: _list(k)))),
  _Api('queryMaps', _Protocol.extended, (ctx, k) async {
    final List<Map<String, dynamic>> maps =
        await ctx.queryMaps(_with(k.sql, r'$1'), params: _list(k));
    return _Outcome([for (final map in maps) map.values.toList()], null);
  }),
  _Api('queryMaps binary', _Protocol.extended, (ctx, k) async {
    final List<Map<String, dynamic>> maps = await ctx.queryMaps(
        _with(k.sql, r'$1'),
        params: _list(k),
        requireBinaryResults: true);
    return _Outcome([for (final map in maps) map.values.toList()], null);
  }),
  _Api('queryTyped', _Protocol.extended, (ctx, k) async {
    final List<List<Object?>> rows = await ctx.queryTyped<List<Object?>>(
        _with(k.sql, '@p'), (RowView row) => List<Object?>.of(row.values),
        params: _map(k), placeholderIdentifier: PlaceholderIdentifier.atSign);
    return _Outcome(rows, null);
  }),
  _Api('queryEach', _Protocol.extended, (ctx, k) async {
    final rows = <List<Object?>>[];
    await ctx.queryEach(_with(k.sql, '?'),
        (RowView row) => rows.add(List<Object?>.of(row.values)),
        params: _list(k),
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
    return _Outcome(rows, null);
  }),
  _Api('prepareStatement + executeStatement', _Protocol.extended,
      (ctx, k) async {
    final Query statement =
        await ctx.prepareStatement(_with(k.sql, r'$1'), _list(k));
    return _results(await ctx.executeStatement(statement));
  }, pool: false),
  _Api('prepareStatement :name + executeStatement isDeallocate',
      _Protocol.extended, (ctx, k) async {
    final Query statement = await ctx.prepareStatement(
        _with(k.sql, ':p'), _map(k),
        placeholderIdentifier: PlaceholderIdentifier.colon);
    return _results(await ctx.executeStatement(statement, isDeallocate: true));
  }, pool: false),
  _Api(
      'prepareStatement unnamed + executeStatementAsStream', _Protocol.extended,
      (ctx, k) async {
    final Query statement = await ctx.prepareStatement(
        _with(k.sql, r'$1'), _list(k),
        isUnamedStatement: true);
    final ResultStream stream = await ctx.executeStatementAsStream(statement);
    final rows = await stream.toList();
    return _Outcome(
        [for (final row in rows) row.toList()], stream.rowsAffected.value);
  }, pool: false),
];

int _sentinelValue = 1000;

/// A statement whose result proves that the connection answers the command
/// it was just sent, not a leftover of the previous one.
_Kind _sentinel() {
  final value = ++_sentinelValue;
  return _Kind('sentinel', 'select {p}::int4 + 0 as sentinel',
      param: value,
      rows: [
        [value]
      ],
      affected: 1);
}

Matcher _sqlState(String code) => isA<PostgresqlException>()
    .having((e) => e.serverErrorCode, 'SQLSTATE', code);

class _Rollback implements Exception {}

Future<void> _expectOutcome(_Api api, _Kind kind, dynamic ctx) async {
  final failure = kind.failure(api.protocol);
  final call = api.run(ctx, kind).timeout(_callTimeout);
  if (failure != null) {
    await expectLater(call, throwsA(_sqlState(failure)),
        reason: '${api.name} / ${kind.name}');
    return;
  }
  final outcome = await call;
  if (outcome.rows != null) {
    final rows = outcome.rows!;
    if (kind.sortRows) {
      rows.sort((a, b) => (a.first as int).compareTo(b.first as int));
    }
    expect(rows, kind.rows, reason: '${api.name} / ${kind.name}: rows');
  }
  if (outcome.affected != null) {
    expect(outcome.affected, kind.affected,
        reason: '${api.name} / ${kind.name}: rowsAffected');
  }
}

/// Where the calls run.
enum _Context {
  connection,
  transaction,
  zone,
  beginTransaction,
  pool,
  poolTransaction
}

void main() {
  late CoreConnection admin;

  setUpAll(() async {
    admin = CoreConnection.fromSettings(_settings());
    await admin.connect();
    await admin
        .execute('drop table if exists cov_m; drop table if exists cov_m_tmp; '
            'create table cov_m (id serial primary key, v int4)');
    await admin
        .execute('create or replace function cov_notify(i int4) returns int4 '
            r"language plpgsql as $$ begin raise notice 'cov row %', i; "
            r'return i; end $$');
  });

  tearDownAll(() async {
    await admin
        .execute('drop table if exists cov_m; drop table if exists cov_m_tmp; '
            'drop function if exists cov_notify(int4)');
    await admin.close();
  });

  for (final context in _Context.values) {
    group(context.name, () {
      CoreConnection? connection;
      PostgreSqlPool? pool;
      final notices = <ServerNotice>[];
      StreamSubscription<dynamic>? subscription;

      final usesPool =
          context == _Context.pool || context == _Context.poolTransaction;

      Future<void> open() async {
        if (usesPool) {
          // One slot: every operation reuses the same physical connection.
          pool = PostgreSqlPool(1, _settings());
        } else {
          final opened = CoreConnection.fromSettings(_settings());
          await opened.connect();
          subscription = opened.notices.listen((notice) {
            if (notice is ServerNotice) notices.add(notice);
          });
          connection = opened;
        }
      }

      Future<void> close() async {
        await subscription?.cancel();
        subscription = null;
        await connection?.close();
        connection = null;
        await pool?.close();
        pool = null;
      }

      Future<int> reset() async {
        if (usesPool) return pool!.execute(_reset).timeout(_callTimeout);
        return connection!.execute(_reset).timeout(_callTimeout);
      }

      setUpAll(open);
      tearDownAll(close);

      setUp(() async {
        // A test that left the connection stuck must not fail the next ones.
        try {
          await reset();
        } catch (_) {
          await close();
          await open();
          await reset();
        }
        notices.clear();
      });

      /// Runs [kind] then the sentinel through [api] in [context]. In a
      /// transaction, a failed statement makes the next command fail with
      /// 25P02 and the sentinel runs after the rollback.
      Future<void> runOnce(_Api api, _Kind kind) async {
        final failure = kind.failure(api.protocol);
        Future<void> body(dynamic ctx) async {
          await _expectOutcome(api, kind, ctx);
          if (failure != null) {
            await expectLater(api.run(ctx, _sentinel()).timeout(_callTimeout),
                throwsA(_sqlState('25P02')),
                reason: 'the failed statement aborts the transaction');
          } else {
            await _expectOutcome(api, _sentinel(), ctx);
          }
        }

        switch (context) {
          case _Context.connection:
            await _expectOutcome(api, kind, connection);
          case _Context.pool:
            await _expectOutcome(api, kind, pool);
          case _Context.transaction:
          case _Context.zone:
            try {
              await connection!.runInTransaction((tx) async {
                await body(context == _Context.zone ? connection : tx);
                if (failure != null) throw _Rollback();
              }).timeout(_callTimeout * 3);
            } on _Rollback {
              // Expected for a failing statement.
            }
            expect(connection!.transactionState, TransactionState.none);
          case _Context.beginTransaction:
            final tx = await connection!.beginTransaction();
            try {
              await body(tx);
            } finally {
              if (failure != null) {
                await connection!.rollBack(tx);
              } else {
                await connection!.commit(tx);
              }
            }
            expect(connection!.transactionState, TransactionState.none);
          case _Context.poolTransaction:
            try {
              await pool!.runInTransaction((tx) async {
                await body(tx);
                if (failure != null) throw _Rollback();
              }).timeout(_callTimeout * 3);
            } on _Rollback {
              // Expected for a failing statement.
            }
        }
        // The next command on the same connection, outside any transaction.
        await _expectOutcome(api, _sentinel(), usesPool ? pool : connection);
      }

      for (final api in _apis) {
        if (usesPool && !api.pool) continue;
        group(api.name, () {
          for (final kind in _kinds) {
            test(kind.name, () async {
              await runOnce(api, kind);
              if (kind.notice != null &&
                  kind.failure(api.protocol) == null &&
                  !usesPool) {
                await Future<void>.delayed(Duration.zero);
                expect(notices.map((n) => '${n.code} ${n.message}'),
                    contains(allOf(startsWith('00000'), contains(kind.notice))),
                    reason: 'NOTICE delivered on CoreConnection.notices');
              }
              // Warm: the statement is now cached (when the API caches).
              await reset();
              await runOnce(api, kind);
            });
          }
        });
      }
    });
  }

  group('pipelined', () {
    late CoreConnection connection;

    setUpAll(() async {
      connection = CoreConnection.fromSettings(_settings());
      await connection.connect();
    });
    tearDownAll(() => connection.close());
    setUp(() => connection.execute(_reset));

    /// Issues every call before awaiting any: they queue on one socket and
    /// each must still get its own response.
    Future<void> burst(List<(_Api, _Kind)> calls) async {
      final pending = <Future<void>>[];
      for (final (api, kind) in calls) {
        pending.add(_expectOutcome(api, kind, connection));
        pending.add(_expectOutcome(api, _sentinel(), connection));
      }
      await Future.wait(pending);
    }

    final readers = [
      for (final kind in _kinds)
        if (!kind.writes) kind
    ];

    for (final api in _apis) {
      test(api.name, () async {
        await burst([for (final kind in readers) (api, kind)]);
        // Warm.
        await burst([for (final kind in readers) (api, kind)]);
      });
    }

    test('every entry point at once', () async {
      await burst([
        for (final api in _apis)
          for (final kind in readers) (api, kind)
      ]);
      expect(await connection.checkHealth(), isTrue);
    });
  });

  group('misc', () {
    late CoreConnection connection;

    setUpAll(() async {
      connection = CoreConnection.fromSettings(_settings());
      await connection.connect();
    });
    tearDownAll(() => connection.close());

    Future<void> next() async => expect(
        (await connection.queryNamed('select 42::int4', const [])).single[0],
        42);

    test('a stream abandoned after its first row', () async {
      const sql = 'select g::int4 from generate_series(1, 50000) g';
      final simple = await connection.querySimpleAsStream(sql);
      expect((await simple.first)[0], 1);
      await next();
      final statement = await connection.prepareStatement(sql, const []);
      final prepared = await connection.executeStatementAsStream(statement);
      expect((await prepared.take(2).toList()).map((r) => r[0]), [1, 2]);
      await next();
    });

    test('a stream never listened to', () async {
      await connection.querySimpleAsStream('select 1; select 1 / 0');
      await next();
    });

    test('parameter count mismatch (08P01) then the right count', () async {
      const sql = r'select $1::int4 + $2::int4';
      for (final cached in [true, false]) {
        await expectLater(
            connection.queryNamed(sql, [1], isDeallocate: !cached),
            throwsA(_sqlState('08P01')));
        await next();
        expect((await connection.queryNamed(sql, [1, 2])).single[0], 3);
      }
    });

    test('a NUL character in a text parameter (22021)', () async {
      await expectLater(connection.queryNamed(r'select $1::text', ['a b']),
          throwsA(_sqlState('22021')));
      await next();
    });

    test('a missing named parameter fails before reaching the server',
        () async {
      await expectLater(
          connection.queryNamed('select :a::int4, :b::int4', {'a': 1},
              placeholderIdentifier: PlaceholderIdentifier.colon),
          throwsArgumentError);
      await expectLater(
          connection.queryNamed(r'select $1', {'a': 1}), throwsArgumentError);
      await next();
    });

    test('large results across many socket reads', () async {
      const sql = "select g::int4, repeat('x', g % 50) from "
          'generate_series(1, 100000) g';
      for (final binary in [false, true, false]) {
        var count = 0;
        var sum = 0;
        await connection.queryEach(sql, (row) {
          count++;
          sum += row.getInt(0)!;
          expect((row[1] as String).length, (row.getInt(0)!) % 50);
        }, requireBinaryResults: binary);
        expect(count, 100000);
        expect(sum, 100000 * 100001 ~/ 2);
      }
      final simple = await connection.querySimple(sql);
      expect(simple.length, 100000);
      expect(simple.rowsAffected.value, 100000);
      await next();
    });

    test('notifications while idle, while busy and from its own transaction',
        () async {
      final other = CoreConnection.fromSettings(_settings());
      await other.connect();
      addTearDown(other.close);
      final received = <String>[];
      final subscription = connection.notifications
          .listen((n) => received.add((n as Map)['payload'] as String));
      addTearDown(subscription.cancel);
      await connection.execute('listen cov_channel');
      addTearDown(() => connection.execute('unlisten cov_channel'));

      await other.execute("notify cov_channel, 'idle ç'");
      final busy = connection.queryNamed(
          'select pg_sleep(0.3)::text, g::int4 from generate_series(1, 3) g',
          const []);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await other.execute("notify cov_channel, 'busy'");
      expect([for (final row in await busy) row[1]], [1, 2, 3]);
      await connection
          .runInTransaction((tx) => tx.execute("notify cov_channel, 'own'"));
      await next();
      for (var i = 0; i < 100 && received.length < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(received, unorderedEquals(['idle ç', 'busy', 'own']));
      await next();
    });

    test('a callback that swallows an error: nothing is committed', () async {
      await connection.execute('create temp table cov_m_swallow (v int4)');
      try {
        await connection.runInTransaction((tx) async {
          await tx.execute('insert into cov_m_swallow values (1)');
          try {
            await tx.execute('select 1 / 0');
          } on PostgresqlException {
            // Swallowed: PostgreSQL turns the COMMIT into a ROLLBACK.
          }
        });
      } catch (_) {
        // Whether runInTransaction reports it is not asserted here.
      }
      expect(
          (await connection.queryNamed(
                  'select count(*)::int4 from cov_m_swallow', const []))
              .single[0],
          0);
      expect(connection.transactionState, TransactionState.none);
    });
  });
}
