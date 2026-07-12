# Dargres 4.0.0 performance migration guide

dargres 4.0.0 is a breaking, performance-focused release. It adds direct row
decoding, a bounded prepared-statement cache, safer connection and pool
lifecycle rules, PostgreSQL wire-level cancellation, and optional generated
IANA timezone data. It requires Dart `^3.6.0`.

This guide explains which query API to choose, which objects the application
owns, and how to migrate lifecycle, timeout, pool, and timezone configuration.

## Choose the result shape first

The direct APIs are available on `CoreConnection`, `TransactionContext`, and
`PostgreSqlPool`.

| Requirement | API | Result and ownership |
|---|---|---|
| Stable maps for JSON or dynamic code | `queryMaps` | One independent `Map<String, dynamic>` per row |
| Domain entities | `queryTyped<T>` | A `List<T>` containing objects created by the synchronous mapper |
| Immediate aggregation or side effects | `queryEach` | No driver-owned row collection; the callback consumes each row synchronously |
| Compatibility with `Results` and `Row` | `queryCached` | Materialized `Results`; only statement metadata is cached |
| Multiple statements or Simple Query Protocol behavior | `querySimple` | Materialized `Results` using the simple protocol |
| Affected-row count for command SQL | `execute` | `Future<int>` |

Use the most specific final shape. For example, do not build `Results`, convert
it to maps, and then build entities when `queryTyped<T>` can create the entities
directly.

### Replace `Results.toMaps()` with `queryMaps`

Before:

```dart
final Results result = await connection.queryUnnamed(
  r'SELECT id, name FROM people WHERE active = $1',
  [true],
);
final maps = result.toMaps();
```

After:

```dart
final maps = await connection.queryMaps(
  r'SELECT id, name FROM people WHERE active = $1',
  params: [true],
);
```

Each returned map is stable and independently owned. If the result contains
duplicate column names, the last column wins; use SQL aliases when every value
must be retained.

### Replace manual `Row` mapping with `queryTyped<T>`

Before:

```dart
final result = await connection.queryUnnamed(
  r'SELECT id, name FROM people WHERE active = $1',
  [true],
);
final people = result
    .map((row) => Person(row[0] as int, row[1] as String))
    .toList();
```

After:

```dart
final people = await connection.queryTyped<Person>(
  r'SELECT id, name FROM people WHERE active = $1',
  (row) => Person(
    row.getInt(0)!,
    row.getString('name')!,
  ),
  params: [true],
);
```

The driver does not create an intermediate `Row` or `Map`. The returned
`List<Person>` and each `Person` are intentional application-owned allocations.

### Use `queryEach` for synchronous consumption

```dart
var total = 0;
await connection.queryEach(
  r'SELECT amount FROM invoice WHERE account_id = $1',
  (row) {
    total += row.getInt(0)!;
  },
  params: [accountId],
);
```

Do not move an I/O-bound asynchronous loop to `queryEach` without redesigning
the work. Its callback is deliberately synchronous.

### Use `queryCached` when `Results` is still required

```dart
final Results result = await connection.queryCached(
  r'SELECT id, name FROM people WHERE id = $1',
  params: [42],
);
```

`queryCached` executes the SQL on every call. It caches the prepared statement
and result schema, never result rows.

## `Row` values are now `Object?`

`Row` now implements `ListBase<Object?>`. Indexed access returns `Object?`, and
`toList()` returns `List<Object?>`. Code that relied on implicit `dynamic`
assignment must cast or check the value explicitly.

Before:

```dart
final result = await connection.querySimple('SELECT id FROM people');
final int id = result.first[0];
```

After:

```dart
final result = await connection.querySimple('SELECT id FROM people');
final id = result.first[0] as int;
```

`RowView.operator []` also returns `Object?`. In direct APIs, prefer its typed
accessors such as `getInt`, `getString`, `getBool`, `getDateTime`, and
`getBytes`; these return nullable values.

## `RowView` is borrowed, not owned

`queryTyped` and `queryEach` reuse one `RowView` and one fixed-length
`row.values` list while decoding a result. They are valid only during the
current synchronous mapper or callback. Retaining either reference makes it
observe later rows.

Incorrect:

```dart
final retained = <RowView>[];
await connection.queryEach('SELECT id FROM people', retained.add);
```

Correct, with explicit application ownership:

```dart
final ids = <int>[];
await connection.queryEach('SELECT id FROM people', (row) {
  ids.add(row.getInt('id')!);
});
```

Copy the values during the callback when a raw row must survive:

```dart
final rows = <List<Object?>>[];
await connection.queryEach('SELECT id, name FROM people', (row) {
  rows.add(List<Object?>.of(row.values));
});
```

This is a shallow copy. Copy nested mutable values separately when the
application needs independent ownership.

The mapper type is `T Function(RowView)` and the callback type is
`void Function(RowView)`. Returning a `Future` does not make `queryEach` await
it. Extract owned data first and perform asynchronous work afterward.

A synchronous mapper or callback exception is reported by the query `Future`.
Before completing that future, the driver drains the PostgreSQL response to
`ReadyForQuery`, so the connection remains protocol-aligned.

## Placeholder styles are explicit

The four direct APIs accept named `params` and `placeholderIdentifier`
arguments. Placeholder style is never auto-detected.

| SQL style | Identifier | Required `params` type |
|---|---|---|
| `$1`, `$2`, ... | `PlaceholderIdentifier.pgDefault` | `List` |
| `?` | `PlaceholderIdentifier.onlyQuestionMark` | `List` |
| `:name` | `PlaceholderIdentifier.colon` | `Map` |
| `@name` | `PlaceholderIdentifier.atSign` | `Map` |

Native PostgreSQL placeholders are the default:

```dart
final rows = await connection.queryMaps(
  r'SELECT id, name FROM people WHERE id = $1',
  params: [42],
);
```

Question-mark placeholders must be enabled explicitly:

```dart
final rows = await connection.queryMaps(
  'SELECT id, name FROM people WHERE id = ?',
  params: [42],
  placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
);
```

Named placeholders use a map:

```dart
final rows = await connection.queryMaps(
  'SELECT id, name FROM people WHERE id = :id OR manager_id = :id',
  params: {'id': 42},
  placeholderIdentifier: PlaceholderIdentifier.colon,
);
```

Repeated named placeholders reuse one PostgreSQL parameter position. Text that
looks like a placeholder inside quoted strings, quoted identifiers, line or
nested block comments, and dollar-quoted bodies is preserved.

PostgreSQL also uses `?`, `?|`, and `?&` as JSON operators. Keep the default
`$n` mode for SQL containing those operators. In question-mark mode, every
unquoted `?` token is intentionally treated as a parameter.

Passing the wrong container type throws before the query is sent. Do not work
around this rule by concatenating values into SQL.

## Statement cache and binary results

Each physical `CoreConnection` owns a bounded LRU cache. The exact rewritten
SQL string is the key, so whitespace and comments can create distinct entries.
Connections inside a pool warm independently.

| State | Protocol batch | Result format |
|---|---|---|
| Cold cache miss | `Parse + Describe + Bind + Execute + Sync`, one round trip | Text by default |
| Warm cache hit | `Bind + Execute + Sync`, one round trip | Binary for supported columns, text fallback for others |
| Cache disabled | Unnamed cold path | Text by default |

Parameters remain text-encoded. Selective binary decoding currently covers the
supported scalar OIDs, including booleans, byte arrays, integer and floating
types, text types, dates and timestamps, UUID, JSON, and JSONB. Types without a
complete binary decoder, including `numeric` and arrays, remain on the text
fallback path.

Configure cache capacity per physical connection:

```dart
final settings = ConnectionSettings(
  user: 'app',
  password: 'secret',
  database: 'app',
  statementCacheCapacity: 128,
);
final connection = CoreConnection.fromSettings(settings);
```

- The default is `64` entries.
- `0` disables retention.
- A negative value is rejected.
- `statementCacheLength`, `statementCacheHits`, `statementCacheMisses`,
  `statementCacheEvictions`, and `statementCacheInvalidations` are diagnostic
  counters.
- `clearStatementCache()` invalidates local metadata and schedules safe server
  closes where appropriate.

`DEALLOCATE ALL`, `DISCARD ALL`, reconnect, and terminal connection teardown
invalidate local cache state. After application-controlled DDL that can change
a result schema, call `clearStatementCache()` before reusing affected SQL. The
driver does not transparently replay an arbitrary failed command because doing
so could duplicate side effects.

### Strict binary results are opt-in

All four direct APIs accept `requireBinaryResults: true`:

```dart
final rows = await connection.queryMaps(
  r'SELECT id, created_at FROM event WHERE id > $1',
  params: [42],
  requireBinaryResults: true,
);
```

Strict mode requests binary for every result column and throws
`UnsupportedError` when PostgreSQL reports an OID without a complete decoder.
On a cold query, PostgreSQL may already have executed the statement before its
result OIDs are known. dargres never retries that strict failure, so side
effects occur at most once. Use strict mode only for controlled, tested result
schemas. The default selective mode is safer for general SQL.

## Prepared statements have independent execution state

An explicitly prepared `Query` is a handle to server-side statement metadata,
not the mutable state of its most recent execution. Every
`executeStatement`/`executeStatementAsStream` call creates independent
controller, error, row-count, and affected-row state.

Do not read `query.rowCount`, `query.rowsAffected`, or `query.error` from the
prepared handle as a record of the last execution. Read rows, affected counts,
and errors from the returned `Results`, `ResultStream`, or query future.
`QueryState` and `query.state` were removed.

Explicit prepared handles remain available on physical connection and
transaction contexts. They are intentionally absent from `PostgreSqlPool`
because a handle cannot safely escape the lease of the physical connection
that owns it. Prefer the direct APIs and their connection-local cache for pool
work.

## The pool is bounded and lease-based

`PostgreSqlPool` no longer implements `ConnectionInterface`. It exposes
operation-scoped methods such as `execute`, `querySimple`, `queryUnnamed`,
`queryNamed`, the four direct APIs, and `runInTransaction`. Separate pool-level
`connect`, `beginTransaction`/`commit`/`rollBack`, stream, and explicit prepared
handle methods were removed.

```dart
final settings = ConnectionSettings(
  user: 'app',
  password: 'secret',
  database: 'app',
  statementCacheCapacity: 128,
);

final pool = PostgreSqlPool(
  8,
  settings,
  allowAttemptToReconnect: true,
  timeout: const Duration(seconds: 30),
  maxPendingOperations: 256,
);

final people = await pool.queryTyped<Person>(
  r'SELECT id, name FROM people WHERE active = $1',
  (row) => Person(row.getInt(0)!, row.getString(1)!),
  params: [true],
);

await pool.runInTransaction((transaction) async {
  await transaction.execute('UPDATE account SET active = true');
}, timeout: const Duration(seconds: 15));
```

The pool opens at most `size` physical connections. Each operation owns one
fixed slot for its complete lifetime; work above `size` waits in a FIFO rather
than opening another socket. The FIFO is bounded by `maxPendingOperations`
(default `1024`). New work above that bound fails with
`PoolQueueFullException` before execution.

The pool timeout covers admission and provides the default execution deadline.
Methods that expose a `timeout` argument can override their execution deadline.
Direct `ConnectionSettings.commandTimeout` is a separate server-cancellation
mechanism described below.

When a running pool operation times out:

1. The public future completes with `TimeoutException`.
2. The leased socket is closed and can never be returned to the available set.
3. The slot remains quarantined until the original future or transaction
   callback actually settles.
4. A new connection is opened in the same slot before later work uses it.

Quarantine prevents a timed-out callback from sharing a physical connection
with a later operation. If user code never settles, that slot intentionally
remains unavailable rather than violating isolation.

The unsafe `restartOnTimeout` and transaction `timeoutInner` options were
removed. There is no mode that returns a socket to the pool while its previous
work may still be running.

Pool diagnostics are available without opening another connection:

- `openConnectionCount`
- `leasedConnectionCount`
- `pendingOperationCount`
- `rejectedOperationCount`
- `queuedOperationTimeoutCount`
- `operationTimeoutCount`
- `connectionReplacementCount`
- `connectionReplacementFailureCount`

When sizing PostgreSQL `max_connections`, account for every process and
isolate: approximately `pool.size * numberOfPools`, plus direct,
administrative, migration, and monitoring connections.

## Connection lifecycle, reconnect, and health checks

Concurrent calls to `connect()` on one `CoreConnection` share the same complete
TCP, SSL, authentication, and `ReadyForQuery` operation. `close()` is terminal:
it invalidates pending opens and an older socket cannot resurrect the object.
Create a new `CoreConnection` after an intentional close.

Automatic reconnect is opt-in and applies after a recoverable disconnection,
not after terminal close. Active and already queued commands fail when the
socket is lost; dargres does not replay them because their server-side outcome
may be unknown. A later operation may reconnect when enabled.

```dart
final settings = ConnectionSettings(
  user: 'app',
  password: 'secret',
  database: 'app',
  tcpKeepalive: true,
  allowAttemptToReconnect: true,
  reconnectPolicy: const ReconnectPolicy(
    maxAttempts: 8,
    initialDelay: Duration(milliseconds: 100),
    maxDelay: Duration(seconds: 5),
    jitterFactor: 0.2,
  ),
);
```

`maxAttempts` counts actual reconnect attempts. Delays use bounded exponential
backoff and jitter; concurrent reconnect callers share one cycle. A zero-attempt
policy disables reconnect.

Use `ping()` for a health round trip that throws on failure. Use
`checkHealth()` when a boolean is more convenient. Neither method starts a
background timer; schedule service-level probes explicitly if needed.

## Command timeout and PostgreSQL `CancelRequest`

Direct command timeout is disabled by default so the normal hot path does not
allocate one Dart `Timer` per command. Long-running services should choose an
explicit bound that matches their workload:

```dart
final settings = ConnectionSettings(
  user: 'app',
  password: 'secret',
  database: 'app',
  commandTimeout: const Duration(seconds: 30),
  cancelGracePeriod: const Duration(seconds: 3),
);
```

When `commandTimeout` expires, dargres sends PostgreSQL's out-of-band
`CancelRequest` on a separate short-lived socket. New work is held behind a
barrier until that request socket closes, preventing a late cancel packet from
targeting the next command. The original connection then has up to
`cancelGracePeriod` to reach `ReadyForQuery`; otherwise it is destroyed.

`cancelCurrentQuery()` performs explicit server-side cancellation and returns
`false` when the connection is idle. Cancellation does not make an arbitrary
write safe to retry; the application must decide based on its transaction and
idempotency rules.

Pool operation timeout and direct command timeout solve different problems:

- Pool timeout bounds the public pool operation and quarantines its lease.
- Command timeout asks PostgreSQL to cancel the active command and can preserve
  the same connection when the server returns to `ReadyForQuery` in time.

## Timezone behavior and generated IANA data

PostgreSQL `timestamptz` stores an absolute instant. By default, dargres returns
that instant as a UTC `DateTime`; this is exact and does not initialize timezone
data.

Enable the internal generated IANA database only when the application must
materialize the same instant in a named zone:

```dart
final timeZone = TimeZoneSettings(
  'America/Sao_Paulo',
  forceDecodeTimestamptzAsUTC: false,
  useIanaTimeZoneDatabase: true,
  ianaTimeZoneDatabaseScope: PgTimeZoneDatabaseScope.latestAll,
);

final connection = CoreConnection(
  'app',
  password: 'secret',
  database: 'app',
  timeZone: timeZone,
);
```

`latestAll` preserves full historical transitions. `latest10y` is smaller and
is suitable only when the application's date range fits that generated window.
The implementation uses pure Dart: no FFI, operating-system timezone file, or
extra PostgreSQL query is required at runtime.

Cached binary date/timestamp decoders read the current `ServerInfo` timezone.
Therefore `SET TIME ZONE` takes effect on later cache hits without rebuilding
the prepared-statement schema.

Generated timezone files are versioned and must not be edited manually. To
regenerate the compact database from the latest IANA release:

```powershell
dart run scripts/generate_pg_timezone_data.dart
```

To regenerate full history:

```powershell
dart run scripts/generate_pg_timezone_data.dart `
  --scope latest_all `
  --output lib/src/utils/pg_timezone/timezone/pg_timezone_data_all.dart
```

Use `--iana <file-or-directory>` for an already downloaded source and
`--iana-version <version>` to pin published input. Run the timezone unit and
integration tests after regeneration.

## Zero runtime package dependencies

dargres 4.0.0 has no runtime package dependencies. The previous `crypto`,
`convert`, `collection`, `enough_convert`, `pool`, and `path` dependencies were
replaced by internal pure-Dart implementations covered by tests. Only test and
lint tooling remains under `dev_dependencies`.

Applications should import dargres public APIs rather than its internal
implementations; zero dependencies does not make `lib/src` a stable public
surface.

## Migration checklist

1. Upgrade to dargres `4.0.0` and Dart `^3.6.0`.
2. Choose the final result shape: maps, domain entities, synchronous callback,
   or compatible `Results`.
3. Replace `Results.toMaps()` and manual `Row` mapping where a direct API fits.
4. Add casts or type checks where legacy `Row` access now returns `Object?`.
5. Treat `RowView` and `row.values` as borrowed callback-only storage; copy or
   construct owned values before returning.
6. Remove asynchronous `queryEach` callbacks. Move asynchronous work after
   extraction or use a different flow-control design.
7. Select placeholders explicitly: `List` for `$n`/`?`, `Map` for `:`/`@`.
8. Keep `$n` mode for SQL containing PostgreSQL JSON question-mark operators.
9. Stop observing execution state on a prepared `Query` handle; use the result
   returned by each execution.
10. Set `statementCacheCapacity` per physical connection and invalidate affected
    entries after application-controlled schema changes.
11. Use `requireBinaryResults` only for controlled schemas and never assume a
    strict cold failure prevented server-side effects.
12. Size pools and PostgreSQL connection limits across every process/isolate.
13. Configure `maxPendingOperations` and operation timeouts. Monitor the
    leased/pending gauges during quarantine and the rejection, timeout, and
    replacement counters.
14. Replace pool-level transaction handles with `runInTransaction`; remove
    `restartOnTimeout` and `timeoutInner` configuration.
15. Decide whether recoverable reconnect is allowed, configure
    `ReconnectPolicy`, and treat `close()` as terminal.
16. Configure `commandTimeout` and `cancelGracePeriod` for long-running services,
    then test cancellation with real PostgreSQL.
17. Choose UTC or explicit IANA decoding, and test `SET TIME ZONE`, historical
    transitions, `NULL`, and infinity behavior used by the application.
18. Measure cold and warm queries separately; warm every physical pool
    connection before drawing cache-performance conclusions.

## Verification

The test suites are split by responsibility:

```powershell
dart test test/unit
dart test test/integration --concurrency=1
dart analyze
```

Integration tests read `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, and
`PGPASSWORD`. Their local defaults are `localhost:5432`, database `postgres`,
and user/password `dart`/`dart`.

Before deploying a long-lived service, also exercise server restart,
reconnection limits, command cancellation, pool saturation, transaction
timeouts, timezone changes, and graceful shutdown under the application's real
concurrency profile.
