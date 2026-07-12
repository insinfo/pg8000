import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

String _env(String name, String fallback) =>
    Platform.environment[name]?.isNotEmpty == true
        ? Platform.environment[name]!
        : fallback;

ConnectionSettings _settings() => ConnectionSettings(
      user: _env('PGUSER', 'dart'),
      password: _env('PGPASSWORD', 'dart'),
      database: _env('PGDATABASE', 'postgres'),
      host: _env('PGHOST', 'localhost'),
      port: int.parse(_env('PGPORT', '5432')),
    );

void main() {
  group('PostgreSqlPool integration', () {
    test('validates queue and per-operation timeout configuration', () async {
      expect(
        () => PostgreSqlPool(1, _settings(), maxPendingOperations: -1),
        throwsArgumentError,
      );

      final pool = PostgreSqlPool(1, _settings());
      await expectLater(
        pool.querySimple('SELECT 1', timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(pool.openConnectionCount, 0);
      final closing = pool.close();
      expect(identical(closing, pool.close()), isTrue);
      await closing;
    });

    test('leases distinct physical connections under concurrency', () async {
      final pool = PostgreSqlPool(2, _settings());
      addTearDown(pool.close);

      final results = await Future.wait(List.generate(
        4,
        (_) => pool.queryMaps(
            'SELECT pg_backend_pid() AS pid FROM pg_sleep(0.05)'),
      ));
      final pids = results.map((rows) => rows.single['pid']).toSet();
      expect(pids, hasLength(2));
      expect(pool.openConnectionCount, 2);
      expect(pool.leasedConnectionCount, 0);
      expect(pool.pendingOperationCount, 0);
    });

    test('owns one connection for the complete transaction', () async {
      final pool = PostgreSqlPool(2, _settings());
      addTearDown(pool.close);

      final pids = await pool.runInTransaction((transaction) async {
        final first = await transaction.queryMaps('SELECT pg_backend_pid() pid');
        final second = await transaction.queryMaps('SELECT pg_backend_pid() pid');
        return <Object?>[first.single['pid'], second.single['pid']];
      });
      expect(pids[0], pids[1]);
    });

    test('forwards explicit question-mark placeholders', () async {
      final pool = PostgreSqlPool(1, _settings());
      addTearDown(pool.close);

      final rows = await pool.queryMaps(
        'SELECT ?::int4 AS value',
        params: const <Object?>[42],
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      expect(rows.single['value'], 42);
    });

    test('forwards strict binary mode through every direct API', () async {
      final pool = PostgreSqlPool(1, _settings());
      addTearDown(pool.close);

      final maps = await pool.queryMaps(
        'SELECT 42::int4 AS value',
        requireBinaryResults: true,
      );
      final typed = await pool.queryTyped<int>(
        'SELECT 43::int4 AS value',
        (row) => row.getInt('value')!,
        requireBinaryResults: true,
      );
      var each = 0;
      await pool.queryEach(
        'SELECT 44::int4 AS value',
        (row) => each = row.getInt('value')!,
        requireBinaryResults: true,
      );
      final cached = await pool.queryCached(
        'SELECT 45::int4 AS value',
        requireBinaryResults: true,
      );

      expect(maps.single['value'], 42);
      expect(typed, [43]);
      expect(each, 44);
      expect(cached.single[0], 45);
    });

    test('replaces a connection closed by an operation timeout', () async {
      final pool = PostgreSqlPool(
        1,
        _settings(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(pool.close);

      await expectLater(
        pool.querySimple(
          'SELECT pg_sleep(0.2)',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
      final rows = await pool.queryMaps('SELECT 42 AS value');
      expect(rows.single['value'], 42);
      expect(pool.operationTimeoutCount, 1);
      expect(pool.connectionReplacementCount, 1);
    });

    test('keeps a timed-out lease until the underlying Future settles',
        () async {
      final pool = PostgreSqlPool(
        1,
        _settings(),
        timeout: const Duration(seconds: 2),
      );
      addTearDown(pool.close);

      final callbackStarted = Completer<void>();
      final releaseCallback = Completer<void>();
      late int timedOutBackendPid;
      final timedOut = pool.runInTransaction<void>((transaction) async {
        final rows =
            await transaction.queryMaps('SELECT pg_backend_pid() AS pid');
        timedOutBackendPid = rows.single['pid'] as int;
        callbackStarted.complete();
        await releaseCallback.future;
      }, timeout: const Duration(milliseconds: 50));

      await callbackStarted.future;
      await expectLater(timedOut, throwsA(isA<TimeoutException>()));
      expect(pool.leasedConnectionCount, 1);
      expect(pool.operationTimeoutCount, 1);

      var queuedCompleted = false;
      final queued = pool
          .queryMaps('SELECT pg_backend_pid() AS pid')
          .whenComplete(() => queuedCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(pool.pendingOperationCount, 1);
      expect(queuedCompleted, isFalse);

      releaseCallback.complete();
      final replacementRows = await queued;
      expect(replacementRows.single['pid'], isNot(timedOutBackendPid));
      expect(pool.connectionReplacementCount, 1);
      expect(pool.leasedConnectionCount, 0);
      expect(pool.pendingOperationCount, 0);
    });

    test('rejects excess work when the public pending limit is reached',
        () async {
      final pool = PostgreSqlPool(
        1,
        _settings(),
        timeout: const Duration(seconds: 2),
        maxPendingOperations: 1,
      );
      addTearDown(pool.close);

      final callbackStarted = Completer<void>();
      final releaseCallback = Completer<void>();
      final first = pool.runInTransaction<void>((_) async {
        callbackStarted.complete();
        await releaseCallback.future;
      });
      await callbackStarted.future;

      final queued = pool.queryMaps('SELECT 1::int4 AS value');
      expect(pool.pendingOperationCount, 1);
      final rejected = pool.queryMaps('SELECT 2::int4 AS value');
      await expectLater(
        rejected,
        throwsA(
          isA<PoolQueueFullException>()
              .having((error) => error.capacity, 'capacity', 1)
              .having((error) => error.maxPending, 'maxPending', 1),
        ),
      );
      expect(pool.rejectedOperationCount, 1);
      expect(pool.pendingOperationCount, 1);

      releaseCallback.complete();
      await first;
      expect((await queued).single['value'], 1);
    });
  });
}
