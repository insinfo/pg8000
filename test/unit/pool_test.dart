import 'dart:async';

import 'package:dargres/src/pool/pool.dart';
import 'package:test/test.dart';

void main() {
  group('Pool', () {
    test('rejects a non-positive capacity', () {
      expect(() => Pool(0), throwsArgumentError);
      expect(() => Pool(-1), throwsArgumentError);
    });

    test('rejects invalid queue limits and wait timeouts', () {
      expect(() => Pool(1, maxPending: -1), throwsArgumentError);
      expect(
        () => Pool(1, timeout: Duration.zero),
        throwsArgumentError,
      );
    });

    test('never runs more callbacks than its capacity', () async {
      final pool = Pool(3);
      var active = 0;
      var maximumActive = 0;

      final results = await Future.wait(List.generate(30, (index) {
        return pool.withResource(() async {
          active++;
          if (active > maximumActive) maximumActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          return index;
        });
      }));

      expect(maximumActive, 3);
      expect(results, orderedEquals(List.generate(30, (index) => index)));
      await pool.close();
    });

    test('grants queued callbacks in FIFO order', () async {
      final pool = Pool(1);
      final releaseFirst = Completer<void>();
      final order = <int>[];

      final first = pool.withResource(() => releaseFirst.future);
      final second = pool.withResource(() => order.add(2));
      final third = pool.withResource(() => order.add(3));
      final fourth = pool.withResource(() => order.add(4));

      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);

      releaseFirst.complete();
      await Future.wait([first, second, third, fourth]);

      expect(order, orderedEquals([2, 3, 4]));
      await pool.close();
    });

    test('rejects deterministically when the bounded FIFO is full', () async {
      final pool = Pool(1, maxPending: 1);
      final releaseFirst = Completer<void>();
      var rejectedCallbackRan = false;

      final first = pool.withResource(() => releaseFirst.future);
      final second = pool.withResource(() => 2);
      final rejected = pool.withResource(() {
        rejectedCallbackRan = true;
        return 3;
      });

      await expectLater(
        rejected,
        throwsA(
          isA<PoolQueueFullException>()
              .having((error) => error.capacity, 'capacity', 1)
              .having((error) => error.maxPending, 'maxPending', 1)
              .having((error) => error.pendingCount, 'pendingCount', 1)
              .having((error) => error.rejectedCount, 'rejectedCount', 1),
        ),
      );
      expect(rejectedCallbackRan, isFalse);
      expect(pool.pendingCount, 1);
      expect(pool.rejectedCount, 1);

      releaseFirst.complete();
      expect(await second, 2);
      await first;
      await pool.close();
    });

    test('returns a slot when a callback fails', () async {
      final pool = Pool(1);
      final failFirst = Completer<void>();

      final first = pool.withResource<void>(() async {
        await failFirst.future;
        throw StateError('failed operation');
      });
      final firstError = expectLater(first, throwsStateError);
      final second = pool.withResource(() => 42);

      failFirst.complete();
      await firstError;
      expect(await second, 42);
      await pool.close();
    });

    test('times out a queued callback without running it', () async {
      final pool = Pool(1, timeout: const Duration(milliseconds: 30));
      final releaseFirst = Completer<void>();
      var queuedCallbackRan = false;

      final first = pool.withResource(() => releaseFirst.future);
      final queued = pool.withResource(() {
        queuedCallbackRan = true;
      });

      await expectLater(
        queued,
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.duration,
            'duration',
            const Duration(milliseconds: 30),
          ),
        ),
      );
      expect(queuedCallbackRan, isFalse);
      expect(pool.timedOutCount, 1);

      releaseFirst.complete();
      await first;
      await pool.close();
    });

    test('close drains accepted work and rejects new work', () async {
      final pool = Pool(1);
      final releaseFirst = Completer<void>();
      var queuedCallbackRan = false;

      final first = pool.withResource(() => releaseFirst.future);
      final queued = pool.withResource(() {
        queuedCallbackRan = true;
      });
      final closing = pool.close();

      expect(identical(closing, pool.close()), isTrue);
      await expectLater(pool.withResource(() => 1), throwsStateError);

      var closeCompleted = false;
      closing.then((_) => closeCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(closeCompleted, isFalse);

      releaseFirst.complete();
      await Future.wait([first, queued, closing]);
      expect(queuedCallbackRan, isTrue);
      expect(closeCompleted, isTrue);
    });
  });
}
