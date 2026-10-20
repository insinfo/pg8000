// Concurrent callers of one CoreConnection: queries issued on the connection
// while another caller's runInTransaction callback runs wait for it (they
// used to fail on the extended protocol), queries from the callback itself
// run in the transaction, and queries and transactions run in arrival order.

import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings({bool queueConcurrentCalls = true}) =>
    ConnectionSettings(
      user: _environment('PGUSER', 'dart'),
      database: _environment('PGDATABASE', 'postgres'),
      host: _environment('PGHOST', 'localhost'),
      port: int.parse(_environment('PGPORT', '5432')),
      password: _environment('PGPASSWORD', 'dart'),
      queueConcurrentCalls: queueConcurrentCalls,
    );

const _insert = 'insert into dargres_queue (name) values (?)';

Future<void> _add(CoreConnection c, String name) =>
    c.queryNamed(_insert, [name],
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);

Future<List<String>> _names(CoreConnection c) async => [
      for (final row in (await c.queryNamed(
              'select name from dargres_queue order by id', const []))
          .rows)
        row[0] as String,
    ];

void main() {
  late CoreConnection conn;

  setUp(() async {
    conn = CoreConnection.fromSettings(_settings());
    await conn.connect();
    await conn.execute('drop table if exists dargres_queue');
    await conn.execute(
        'create table dargres_queue (id serial primary key, name text)');
  });
  tearDown(() async {
    await conn.execute('drop table if exists dargres_queue');
    await conn.close();
  });

  test('a query from outside waits for the transaction and stays outside it',
      () async {
    final entered = Completer<void>();
    final transaction = conn.runInTransaction((tx) async {
      await tx.queryNamed(_insert, ['tx'],
          placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
      entered.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      throw StateError('roll back');
    });
    await entered.future;
    // Extended protocol (it threw "A transaction is active") and simple
    // protocol, issued while the transaction is open.
    final outside = Future.wait([
      _add(conn, 'outside'),
      conn.execute("insert into dargres_queue (name) values ('simple')"),
    ]);
    await expectLater(transaction, throwsStateError);
    await outside;
    expect(await _names(conn), ['outside', 'simple']);
  });

  test('a read from outside sees the transaction only after the commit',
      () async {
    final entered = Completer<void>();
    var committed = false;
    final transaction = conn.runInTransaction((tx) async {
      await tx.execute("insert into dargres_queue (name) values ('a')");
      entered.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      committed = true;
    });
    await entered.future;
    final names = await _names(conn);
    expect(committed, isTrue);
    expect(names, ['a']);
    await transaction;
  });

  test('queries on the connection from the callback run in the transaction',
      () async {
    await expectLater(
        conn.runInTransaction((tx) async {
          await Future.wait([
            for (var i = 0; i < 5; i++) _add(conn, 't$i'),
            conn.execute("insert into dargres_queue (name) values ('s')"),
          ]);
          expect(await _names(conn), hasLength(6));
          throw StateError('roll back');
        }).timeout(const Duration(seconds: 10)),
        throwsStateError);
    expect(await _names(conn), isEmpty);
  });

  test('queries and transactions run in arrival order', () async {
    final entered = Completer<void>();
    final first = conn.runInTransaction((tx) async {
      entered.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tx.execute("insert into dargres_queue (name) values ('first')");
    });
    await entered.future;
    final rest = Future.wait([
      _add(conn, 'q1'),
      conn.runInTransaction((tx) =>
          tx.execute("insert into dargres_queue (name) values ('second')")),
      _add(conn, 'q2'),
      conn.runInTransaction((tx) =>
          tx.execute("insert into dargres_queue (name) values ('third')")),
      conn.execute("insert into dargres_queue (name) values ('q3')"),
    ]);
    await first;
    await rest;
    expect(await _names(conn), ['first', 'q1', 'second', 'q2', 'third', 'q3']);
  });

  test('many concurrent queries and transactions', () async {
    await Future.wait([
      for (var i = 0; i < 60; i++)
        if (i % 6 == 0)
          conn.runInTransaction((tx) async {
            await tx.execute("insert into dargres_queue (name) values ('t$i')");
            await tx.queryNamed('select count(*) from dargres_queue', const []);
          })
        else
          _add(conn, 'q$i'),
    ]);
    expect(await _names(conn), hasLength(60));
  });

  test('runInTransaction inside its own callback is rejected', () async {
    await expectLater(
        conn
            .runInTransaction((tx) => conn.runInTransaction((_) async => 1))
            .timeout(const Duration(seconds: 10)),
        throwsStateError);
    expect(await _names(conn), isEmpty);
  });

  test('a manual beginTransaction keeps the extended-protocol guard', () async {
    final tx = await conn.beginTransaction();
    expect(() => _add(conn, 'x'), throwsStateError);
    await conn.commit(tx);
    await _add(conn, 'after');
    expect(await _names(conn), ['after']);
  });

  test('queueConcurrentCalls: false fails instead of waiting', () async {
    final strict =
        CoreConnection.fromSettings(_settings(queueConcurrentCalls: false));
    await strict.connect();
    addTearDown(strict.close);
    final entered = Completer<void>();
    final transaction = strict.runInTransaction((tx) async {
      entered.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await entered.future;
    await expectLater(_add(strict, 'x'), throwsStateError);
    await expectLater(strict.execute('select 1'), throwsStateError);
    await transaction;
    expect(await strict.execute('select 1'), 1);
  });
}
