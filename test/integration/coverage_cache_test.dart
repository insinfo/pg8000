// The per-connection statement cache against a real server: hits, misses
// and evictions with a small capacity (and the server-side statements that
// really exist), DEALLOCATE ALL / DISCARD ALL, schema changes that invalidate
// a cached plan, and one SQL text used inside and outside a transaction at
// the same time.

import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

String _env(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings({int statementCacheCapacity = 64}) =>
    ConnectionSettings(
      user: _env('PGUSER', 'dart'),
      database: _env('PGDATABASE', 'postgres'),
      host: _env('PGHOST', 'localhost'),
      port: int.parse(_env('PGPORT', '5432')),
      password: _env('PGPASSWORD', 'dart'),
      statementCacheCapacity: statementCacheCapacity,
      commandTimeout: const Duration(seconds: 10),
    );

Future<CoreConnection> _open({int statementCacheCapacity = 64}) async {
  final connection = CoreConnection.fromSettings(
      _settings(statementCacheCapacity: statementCacheCapacity));
  await connection.connect();
  addTearDown(connection.close);
  return connection;
}

Matcher _sqlState(String code) => isA<PostgresqlException>()
    .having((e) => e.serverErrorCode, 'SQLSTATE', code);

/// Named statements that exist on the server. queryUnnamed is not cached
/// and carries the Close messages of evicted statements.
Future<List<String>> _serverStatements(CoreConnection c) async => [
      for (final row in await c.queryUnnamed(
          "select name from pg_prepared_statements where name like 'dargres%' "
          'order by name',
          const []))
        row[0] as String
    ];

Future<int> _value(CoreConnection c, int n) async =>
    (await c.queryNamed('select $n::int4 + \$1::int4', [0])).single[0] as int;

class _Rollback implements Exception {}

void main() {
  group('capacity', () {
    test('hits, misses and LRU evictions match the server statements',
        () async {
      final c = await _open(statementCacheCapacity: 2);
      expect(await _value(c, 1), 1); // miss: [1]
      expect(await _value(c, 2), 2); // miss: [1, 2]
      expect(await _value(c, 1), 1); // hit: [2, 1]
      expect(await _value(c, 3), 3); // miss, evicts 2: [1, 3]
      expect(await _value(c, 1), 1); // hit: [3, 1]
      expect(await _value(c, 2), 2); // miss, evicts 3: [1, 2]
      expect(c.statementCacheMisses, 4);
      expect(c.statementCacheHits, 2);
      expect(c.statementCacheEvictions, 2);
      expect(c.statementCacheLength, 2);
      expect(await _serverStatements(c), hasLength(2),
          reason: 'evicted statements are closed on the server');
    });

    test('capacity 0 caches nothing and leaves no server statement', () async {
      final c = await _open(statementCacheCapacity: 0);
      for (var i = 0; i < 3; i++) {
        expect(await _value(c, 5), 5);
      }
      expect(c.statementCacheLength, 0);
      expect(c.statementCacheHits, 0);
      expect(await _serverStatements(c), isEmpty);
    });

    test('capacity 1 with interleaved concurrent statements', () async {
      final c = await _open(statementCacheCapacity: 1);
      final values = await Future.wait([
        for (var i = 0; i < 60; i++) _value(c, i % 3),
      ]);
      expect(values, [for (var i = 0; i < 60; i++) i % 3]);
      expect(c.statementCacheLength, 1);
      expect(await _serverStatements(c), hasLength(1));
    });

    test('isDeallocate and queryUnnamed do not use the cache', () async {
      final c = await _open();
      await c.queryNamed(r'select $1::int4', [1], isDeallocate: true);
      await c.queryUnnamed(r'select $1::int4', [1]);
      expect(c.statementCacheLength, 0);
      expect(await _serverStatements(c), isEmpty);
    });

    test('a statement whose execution fails is still cached', () async {
      final c = await _open();
      for (var i = 0; i < 2; i++) {
        await expectLater(c.queryNamed(r'select 1 / $1::int4', [0]),
            throwsA(_sqlState('22012')));
      }
      expect(c.statementCacheMisses, 1);
      expect(c.statementCacheHits, 1);
      expect((await c.queryNamed(r'select 1 / $1::int4', [1])).single[0], 1);
    });

    test('a statement that fails to parse is not cached', () async {
      final c = await _open();
      for (var i = 0; i < 2; i++) {
        await expectLater(
            c.queryNamed('selec 1', const []), throwsA(_sqlState('42601')));
      }
      expect(c.statementCacheLength, 0);
      expect(c.statementCacheHits, 0);
      expect(await _value(c, 9), 9);
    });
  });

  group('DEALLOCATE ALL and DISCARD ALL', () {
    for (final reset in [
      'DEALLOCATE ALL',
      'deallocate all',
      '  Deallocate Prepare All',
      'DISCARD ALL',
      'discard all;',
    ]) {
      for (final api in ['execute', 'querySimple', 'queryNamed']) {
        test('"$reset" through $api', () async {
          final c = await _open();
          expect(await _value(c, 1), 1);
          expect(await _value(c, 2), 2);
          expect(c.statementCacheLength, 2);
          switch (api) {
            case 'execute':
              await c.execute(reset);
            case 'querySimple':
              await c.querySimple(reset);
            case 'queryNamed':
              await c.queryNamed(reset, const []);
          }
          // The cached statements are gone on the server: re-prepared, not
          // "prepared statement does not exist" (26000).
          expect(await _value(c, 1), 1);
          expect(await _value(c, 2), 2);
          expect(await _value(c, 2), 2);
          expect(await _serverStatements(c), hasLength(c.statementCacheLength));
        });
      }
    }

    test('DEALLOCATE ALL after other statements of a simple query', () async {
      final c = await _open();
      expect(await _value(c, 1), 1);
      await c.execute('select 1; deallocate all');
      expect(await _value(c, 1), 1);
      expect(await _serverStatements(c), hasLength(c.statementCacheLength));
    });

    test('DEALLOCATE of one cached statement by name', () async {
      final c = await _open();
      expect(await _value(c, 1), 1);
      final [name] = await _serverStatements(c);
      await c.execute('deallocate $name');
      // The cache cannot know: the next call fails once (26000) and
      // drops the entry; the one after re-prepares.
      await expectLater(_value(c, 1), throwsA(_sqlState('26000')));
      expect(await _value(c, 1), 1);
      expect(c.statementCacheInvalidations, 1);
    });

    test('a prepareStatement statement does not survive DEALLOCATE ALL',
        () async {
      final c = await _open();
      final statement = await c.prepareStatement(r'select $1::int4 as v', [4]);
      expect((await c.executeStatement(statement)).single[0], 4);
      await c.execute('deallocate all');
      await expectLater(
          c.executeStatement(statement), throwsA(_sqlState('26000')));
      expect(await _value(c, 3), 3);
    });
  });

  group('schema changes', () {
    late CoreConnection c;
    setUp(() async {
      c = await _open();
      await c.execute('drop table if exists cov_c; '
          'create table cov_c (a int4); insert into cov_c values (1)');
      addTearDown(() => c.execute('drop table if exists cov_c'));
    });

    test('a new column changes the result type of a cached select *', () async {
      expect((await c.queryNamed('select * from cov_c', const [])).single, [1]);
      await c.execute('alter table cov_c add column b text default \'x\'');
      await expectLater(c.queryNamed('select * from cov_c', const []),
          throwsA(_sqlState('0A000')));
      expect(c.statementCacheInvalidations, 1);
      expect((await c.queryNamed('select * from cov_c', const [])).single,
          [1, 'x']);
      expect((await c.queryNamed('select * from cov_c', const [])).single,
          [1, 'x']);
      expect(await _serverStatements(c), hasLength(c.statementCacheLength),
          reason: 'the invalidated statement is closed on the server');
    });

    test('a column type change through queryMaps, typed and each', () async {
      const sql = 'select a from cov_c';
      expect((await c.queryMaps(sql)).single['a'], 1);
      await c.execute('alter table cov_c alter column a type text');
      await expectLater(c.queryMaps(sql), throwsA(_sqlState('0A000')));
      expect((await c.queryMaps(sql)).single['a'], '1');
      expect(await c.queryTyped(sql, (row) => row['a']), ['1']);
      final values = <Object?>[];
      await c.queryEach(sql, (row) => values.add(row['a']));
      expect(values, ['1']);
    });

    test('a recreated table with the same shape is replanned silently',
        () async {
      expect((await c.queryNamed('select a from cov_c', const [])).single, [1]);
      await c.execute('drop table cov_c; create table cov_c (a int4); '
          'insert into cov_c values (2)');
      expect((await c.queryNamed('select a from cov_c', const [])).single, [2]);
    });

    test('inside a transaction the invalid plan aborts it', () async {
      expect((await c.queryNamed('select * from cov_c', const [])).single, [1]);
      await c.execute('alter table cov_c add column b int4');
      await expectLater(
          c.runInTransaction(
              (tx) => tx.queryNamed('select * from cov_c', const [])),
          throwsA(_sqlState('0A000')));
      final rows = await c.runInTransaction(
          (tx) => tx.queryNamed('select * from cov_c', const []));
      expect(rows.single, [1, null]);
    });
  });

  group('one SQL text inside and outside a transaction', () {
    late CoreConnection c;
    setUp(() async {
      c = await _open(statementCacheCapacity: 2);
      await c.execute('drop table if exists cov_c2; '
          'create table cov_c2 (id serial primary key, v int4)');
      addTearDown(() => c.execute('drop table if exists cov_c2'));
    });

    const insert = r'insert into cov_c2 (v) values ($1::int4) returning v';
    const count = 'select count(*)::int4 from cov_c2';

    test('callers outside wait; the callback and they share the cache',
        () async {
      final entered = Completer<void>();
      final transaction = c.runInTransaction((tx) async {
        final inside = await Future.wait([
          for (var i = 0; i < 10; i++) tx.queryNamed(insert, [i]),
          // On the connection from the callback: in the transaction.
          for (var i = 10; i < 20; i++) c.queryNamed(insert, [i]),
        ]);
        entered.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect((await tx.queryNamed(count, const [])).single[0], 20);
        return [for (final rows in inside) rows.single[0]];
      });
      await entered.future;
      // Outside: the same SQL while the transaction is open.
      final outside = Future.wait([
        for (var i = 100; i < 110; i++) c.queryNamed(insert, [i]),
        c.queryNamed(count, const []),
      ]);
      expect(await transaction, [for (var i = 0; i < 20; i++) i]);
      final results = await outside;
      expect([for (final rows in results.take(10)) rows.single[0]],
          [for (var i = 100; i < 110; i++) i]);
      expect(results.last.single[0], 30,
          reason: 'the outside count runs after the commit');
      expect(await _serverStatements(c), hasLength(c.statementCacheLength));
    });

    test('statements prepared in a rolled back transaction stay usable',
        () async {
      await expectLater(c.runInTransaction((tx) async {
        await tx.queryNamed(insert, [1]);
        await tx.queryNamed(count, const []);
        throw _Rollback();
      }), throwsA(isA<_Rollback>()));
      final hits = c.statementCacheHits;
      expect((await c.queryNamed(insert, [2])).single[0], 2);
      expect((await c.queryNamed(count, const [])).single[0], 1);
      expect(c.statementCacheHits, hits + 2);
    });

    test('evictions while transactions and outside callers interleave',
        () async {
      final futures = <Future<Object?>>[];
      for (var i = 0; i < 30; i++) {
        if (i % 5 == 0) {
          futures.add(c.runInTransaction((tx) async {
            final a = await tx.queryNamed(insert, [i]);
            final b = await tx.queryNamed('select $i::int4', const []);
            return [a.single[0], b.single[0]];
          }));
        } else {
          futures.add(c.queryNamed(i.isEven ? insert : 'select $i::int4',
              [if (i.isEven) i]).then((rows) => rows.single[0]));
        }
      }
      final results = await Future.wait(futures);
      for (var i = 0; i < 30; i++) {
        expect(results[i], i % 5 == 0 ? [i, i] : i, reason: 'call $i');
      }
      expect(c.statementCacheLength, 2);
      expect(await _serverStatements(c), hasLength(2));
    });
  });

  group('unnamed prepared statements', () {
    test('another unnamed Parse does not replace a prepared statement',
        () async {
      final c = await _open();
      final a = await c.prepareStatement(r"select 'A'::text, $1::int4", [1],
          isUnamedStatement: true);
      // Any uncached query parses the unnamed statement again.
      expect(
          (await c.queryUnnamed(r"select 'B'::text, $1::int4 + 100", [1]))
              .single,
          ['B', 101]);
      await c.queryNamed('select 1', const [], isDeallocate: true);
      // It executed B: Bind alone runs whatever the unnamed statement is.
      expect((await c.executeStatement(a)).single, ['A', 1]);
      expect((await c.executeStatement(a)).single, ['A', 1]);
    });

    test('concurrent unnamed statements in a transaction', () async {
      final c = await _open();
      final results = await c.runInTransaction((tx) async {
        final statements = await Future.wait([
          for (var i = 0; i < 5; i++)
            tx.prepareStatement(r'select $1::int4 * 10', [i],
                isUnamedStatement: true),
        ]);
        return Future.wait([
          for (final s in statements.reversed)
            tx.executeStatement(s).then((rows) => rows.single[0]),
        ]);
      });
      expect(results, [40, 30, 20, 10, 0]);
    });
  });
}
