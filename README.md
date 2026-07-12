# Dargres

[![CI](https://github.com/insinfo/pg8000/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/pg8000/actions/workflows/dart.yml)
[![Pub package](https://img.shields.io/pub/v/dargres.svg)](https://pub.dev/packages/dargres)

Dargres 4.0.0 is a pure-Dart PostgreSQL driver for Dart 3.6 and later. It
implements PostgreSQL protocol 3.0 directly and has no runtime package
dependencies.

The 4.0 architecture focuses on predictable ownership and low allocation in
result-heavy workloads:

- direct `DataRow` decoding into maps, entities, or a synchronous callback;
- segmented input buffers and batched protocol writes;
- a per-physical-connection LRU prepared-statement cache;
- safe text/binary result selection, with an optional strict binary mode;
- bounded connection pooling with exclusive leases and a bounded FIFO;
- terminal connection lifecycle, bounded reconnect backoff, health checks,
  command timeouts, and PostgreSQL `CancelRequest`;
- opt-in generated IANA timezone data, without FFI or runtime files;
- cleartext, MD5, and SASL/SCRAM-SHA-256 authentication;
- plain TCP, Unix sockets, and TLS.

These design choices do not make every workload allocation-free and do not
replace application-specific benchmarks. `queryMaps` must create maps,
`queryTyped` creates the objects returned by its mapper, and decoded values such
as strings still allocate when their Dart representation requires it.

## Requirements and installation

- Dart SDK `^3.6.0`
- A PostgreSQL server reachable through TCP or a Unix socket

Add the package:

```powershell
dart pub add dargres
```

Import the public API:

```dart
import 'package:dargres/dargres.dart';
```

## Connecting

`ConnectionSettings` is convenient when the same configuration is shared by a
direct connection and a pool:

```dart
final settings = ConnectionSettings(
  user: 'dart',
  password: 'dart',
  database: 'postgres',
  host: 'localhost',
  port: 5432,
  applicationName: 'my_service',
  tcpKeepalive: true,
  connectionTimeout: const Duration(seconds: 10),
  commandTimeout: const Duration(seconds: 30),
  cancelGracePeriod: const Duration(seconds: 5),
  statementCacheCapacity: 64,
);

final connection = CoreConnection.fromSettings(settings);
await connection.connect();

try {
  final rows = await connection.queryMaps(
    r'SELECT current_database() AS database, $1::text AS value',
    params: ['ready'],
  );
  print(rows.single);
} finally {
  await connection.close();
}
```

A direct constructor is also available:

```dart
final connection = CoreConnection(
  'dart',
  password: 'dart',
  database: 'postgres',
);
```

`CoreConnection.fromUri` accepts `postgres://` and `postgresql://` URIs. URI
parsing covers the endpoint, credentials, database, and `sslmode=require`.
Operational options such as reconnect policy, command timeout, cache capacity,
and timezone should be configured with `ConnectionSettings`.

### Lifecycle and reconnect

Concurrent calls to `connect()` share one opening operation through TCP,
optional TLS, authentication, and the first `ReadyForQuery`. Calling `close()`
is terminal for that object: pending opening work is invalidated and the
connection cannot later be resurrected. Create a new `CoreConnection` to
connect after an explicit close.

Reconnect is opt-in:

```dart
final settings = ConnectionSettings(
  user: 'dart',
  password: 'dart',
  database: 'postgres',
  allowAttemptToReconnect: true,
  reconnectPolicy: const ReconnectPolicy(
    maxAttempts: 8,
    initialDelay: Duration(milliseconds: 100),
    maxDelay: Duration(seconds: 5),
    jitterFactor: 0.2,
  ),
);
```

`maxAttempts` counts actual connection attempts. The delay starts at
`initialDelay`, doubles up to `maxDelay`, and is spread by `jitterFactor` to
avoid synchronized reconnect storms. Concurrent callers share one reconnect
cycle. Reconnect is demand-driven; it does not run a background loop.

Reconnect opens a new session for later work. It does not replay a command that
failed when the old socket was lost; replaying SQL could duplicate writes or
other side effects.

### Health checks

Health checks are explicit and create no background schedule:

```dart
await connection.ping();                       // throws on failure
final healthy = await connection.checkHealth(); // returns bool
```

Both perform a small PostgreSQL round trip. They do not trigger reconnect when
the connection is already closed. A false result says that this connection is
not currently usable; it is not a replacement for an application-level
readiness policy.

### Command timeout and cancellation

`connectionTimeout` bounds socket opening and startup/TLS phases.
`commandTimeout` is a separate optional cancellation trigger for a command
executing on the server. Its default is `null`, keeping the normal query path
free of one Dart `Timer` per command. It is not a hard deadline for the public
Future: after its timer expires, opening and flushing the cancellation socket
can take up to `connectionTimeout`, and `cancelGracePeriod` starts after the
cancel packet is sent.

When a command timeout expires, Dargres:

1. opens a separate short-lived socket;
2. sends PostgreSQL's out-of-band `CancelRequest` using the backend key;
3. waits up to `cancelGracePeriod` for the original socket to reach
   `ReadyForQuery`;
4. destroys the original socket if it does not recover.

Explicit cancellation uses the same protocol:

```dart
final longQuery = connection.queryMaps('SELECT pg_sleep(30)');
await Future<void>.delayed(const Duration(milliseconds: 100));

final sent = await connection.cancelCurrentQuery();
if (sent) {
  try {
    await longQuery;
  } catch (error) {
    print(error);
  }
}
```

`cancelCurrentQuery()` returns `false` when there is no active command or when
the command finishes before the cancel packet can be sent. New commands remain
behind a cancellation barrier until the short-lived cancel socket closes, so a
late packet cannot target the next query.

PostgreSQL cancellation inside a transaction follows PostgreSQL semantics: the
transaction can enter the failed state and must be rolled back.

## High-performance query APIs

The recommended result APIs are available on `CoreConnection`,
`TransactionContext`, and `PostgreSqlPool`.

| Need | API | Result ownership |
|---|---|---|
| Dynamic or JSON-ready rows | `queryMaps` | One stable `Map<String, dynamic>` per row |
| Domain objects | `queryTyped<T>` | One application-created `T` per row and a `List<T>` |
| Synchronous aggregation | `queryEach` | No retained result collection in the driver |
| `Results`/`Row` compatibility | `queryCached` | Materialized `Results`; only statement metadata is cached |

### Maps

```dart
final rows = await connection.queryMaps(
  r'SELECT id, name FROM people WHERE id > $1 ORDER BY id',
  params: [100],
);

print(rows.first['name']);
```

The driver decodes each `DataRow` directly into its final map. If a result has
duplicate column names, the last column with a given name wins; use SQL aliases
when every value must be preserved.

### Typed entities

```dart
class Person {
  const Person(this.id, this.name);

  final int id;
  final String name;
}

final people = await connection.queryTyped<Person>(
  r'SELECT id, name FROM people WHERE active = $1 ORDER BY id',
  (row) => Person(
    row.getInt('id')!,
    row.getString('name')!,
  ),
  params: [true],
);
```

`queryTyped` skips intermediate `Row` and map objects. The returned list and
the `Person` instances remain intentional application allocations.

### Consume rows without materializing a result list

```dart
const customerId = 42;
var total = 0;

await connection.queryEach(
  r'SELECT amount FROM invoices WHERE customer_id = $1',
  (row) {
    total += row.getInt(0)!;
  },
  params: [customerId],
);
```

The callback is synchronous and is not awaited. Extract owned data before
starting asynchronous work.

### `RowView` lifetime

`queryTyped` and `queryEach` reuse one `RowView` and one fixed-length backing
list during a query. The view, `row.values`, and closures that read them are
valid only inside the current callback. The next row overwrites the same
storage.

Copy explicitly when a raw row must escape:

```dart
final ownedRows = <List<Object?>>[];

await connection.queryEach('SELECT id, name FROM people', (row) {
  ownedRows.add(List<Object?>.of(row.values));
});
```

`RowView` supports indexes and names through `row[column]`, `get<T>`, and
helpers including `getInt`, `getDouble`, `getNum`, `getString`, `getBool`,
`getDateTime`, and `getBytes`.

### Compatible and protocol-specific APIs

The current API also retains:

- `execute` for a command and affected-row count;
- `querySimple` and `querySimpleAsStream` for PostgreSQL's simple-query
  protocol;
- `queryUnnamed` and `queryNamed` for explicit extended-protocol execution;
- `prepareStatement`, `executeStatement`, and `executeStatementAsStream` for an
  explicit prepared-statement handle.

These APIs materialize or stream `Results`/`Row` and are useful when that is the
shape an integration requires. Prefer the four direct APIs when the
application's final shape is known.

## Placeholders

Placeholder selection is explicit; Dargres does not infer it from SQL.

| Style | Selector | Parameters |
|---|---|---|
| PostgreSQL `$1`, `$2`, ... | `PlaceholderIdentifier.pgDefault` | `List` |
| `?` | `PlaceholderIdentifier.onlyQuestionMark` | `List` |
| `:name` | `PlaceholderIdentifier.colon` | `Map` |
| `@name` | `PlaceholderIdentifier.atSign` | `Map` |

PostgreSQL placeholders are the default:

```dart
final rows = await connection.queryMaps(
  r'SELECT id, name FROM people WHERE id = $1',
  params: [42],
);
```

Question marks are supported explicitly:

```dart
final rows = await connection.queryMaps(
  'SELECT id, name FROM people WHERE id = ?',
  params: [42],
  placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
);
```

Named placeholders use a map, and repeated names reuse the same PostgreSQL
position:

```dart
final rows = await connection.queryMaps(
  'SELECT id FROM people WHERE state = :state OR previous_state = :state',
  params: {'state': 'active'},
  placeholderIdentifier: PlaceholderIdentifier.colon,
);
```

The scanner preserves placeholder-like text in quoted strings, quoted
identifiers, line comments, nested block comments, and dollar-quoted bodies.

PostgreSQL also defines JSON operators named `?`, `?|`, and `?&`. Keep the
default `$n` style for SQL that uses those operators. In explicit question-mark
mode, every unquoted `?` token is intentionally a parameter.

## Statement cache and binary results

Each physical connection owns an LRU prepared-statement cache for
`queryMaps`, `queryTyped`, `queryEach`, `queryCached`, and cached `queryNamed`
execution. The key is the exact rewritten SQL string, so whitespace and
comments matter. Pool connections warm independently.

`statementCacheCapacity` defaults to 64:

- `0` disables statement retention;
- positive values set the maximum entries per physical connection;
- eviction is least-recently-used;
- `statementCacheLength`, `statementCacheHits`,
  `statementCacheMisses`, `statementCacheEvictions`, and
  `statementCacheInvalidations` expose cache state;
- `clearStatementCache()` clears connection-local metadata.

In default safe mode:

- a cold miss sends `Parse + Describe + Bind + Execute + Sync` as one batch and
  requests text results because result OIDs are not known in advance;
- a warm hit sends `Bind + Execute + Sync` and requests binary only for columns
  with complete codecs;
- unsupported binary columns fall back to text.

Current binary result codecs include `bool`, `bytea`, `char`, `name`, `int2`,
`int4`, `int8`, `oid`, `xid`, `text`, `varchar`, `bpchar`, `float4`, `float8`,
`date`, `timestamp`, `timestamptz`, `uuid`, `json`, and `jsonb`. Types such as
`numeric`, arrays, extensions, and custom OIDs use text fallback unless a
binary codec is available.

Strict mode can be selected per direct query:

```dart
final rows = await connection.queryMaps(
  r'SELECT id, created_at FROM events WHERE id > $1',
  params: [100],
  requireBinaryResults: true,
);
```

Strict mode requests binary for every result column, including on a cold
statement, and throws if PostgreSQL reports an unsupported OID. The rejected
SQL is not retried. Use this mode only for result schemas controlled and tested
by the application.

`queryCached` caches prepared-statement metadata, not rows; every call still
executes SQL on PostgreSQL.

## Transactions

Prefer `runInTransaction`. It commits the callback result and attempts rollback
when the callback or commit fails:

```dart
final personId = await connection.runInTransaction<int>((tx) async {
  final rows = await tx.queryMaps(
    r'INSERT INTO people (name) VALUES ($1) RETURNING id',
    params: ['Alex'],
  );
  return rows.single['id'] as int;
});

print(personId);
```

Always execute transactional work through the provided `TransactionContext`,
not through the parent connection.

Manual transaction control is available on a direct connection:

```dart
final tx = await connection.beginTransaction();

try {
  await tx.execute(
    'UPDATE accounts SET enabled = true WHERE account_id = 42',
  );
  await connection.commit(tx);
} catch (_) {
  if (tx.isActive) {
    await connection.rollBack(tx);
  }
  rethrow;
}
```

A `TransactionContext` becomes inactive after commit, rollback, connection
loss, or terminal failure and rejects further work.

## Bounded connection pool

`PostgreSqlPool` is an operation pool, not a `ConnectionInterface`. It exposes
operation-scoped query methods and `runInTransaction`, but not raw connection
handles, explicit prepared-statement handles, stream APIs, or direct
`cancelCurrentQuery()`.

```dart
final settings = ConnectionSettings(
  user: 'dart',
  password: 'dart',
  database: 'postgres',
  commandTimeout: const Duration(seconds: 20),
  allowAttemptToReconnect: true,
  reconnectPolicy: const ReconnectPolicy(
    maxAttempts: 10,
    initialDelay: Duration(milliseconds: 100),
    maxDelay: Duration(seconds: 2),
  ),
);

final pool = PostgreSqlPool(
  8,
  settings,
  allowAttemptToReconnect: true,
  timeout: const Duration(seconds: 30),
  maxPendingOperations: 256,
);

try {
  final rows = await pool.queryMaps(
    r'SELECT id, name FROM people WHERE active = $1',
    params: [true],
  );

  await pool.runInTransaction((tx) async {
    await tx.execute('UPDATE job SET claimed = true WHERE job_id = 42');
  }, timeout: const Duration(seconds: 10));

  print(rows.length);
} finally {
  await pool.close();
}
```

The pool initializes at most `size` physical connections and gives one
exclusive connection lease to each accepted operation or transaction. Work
above `size` waits in a FIFO; it does not open additional sockets. Size
PostgreSQL's `max_connections` for all pools, processes, isolates, direct
connections, and administrative headroom.

`maxPendingOperations` defaults to 1024. When the FIFO is full, new work fails
before execution with `PoolQueueFullException` instead of growing memory
without bound.

### Pool timeouts and quarantine

The pool `timeout` defaults to 300 seconds. The configured default supplies two
separate clocks:

- a FIFO wait timeout while all permits are leased;
- an execution timeout started after a physical connection has been leased.

`execute`, `querySimple`, `queryUnnamed`, `queryNamed`, and
`runInTransaction` accept a per-call `timeout` override for the execution clock.
That override does not replace the pool-wide FIFO timeout and does not include
connection opening or replacement. The direct fast pool methods currently use
the pool's configured default execution timeout.

If execution times out, the public future completes with `TimeoutException`,
the physical connection is closed, and its lease remains quarantined until the
underlying operation or transaction callback actually settles. The pool then
replaces the connection in the same slot before reuse. This prevents timed-out
work from sharing a slot with later work.

A transaction callback that never settles keeps its slot quarantined. Dargres
does not release that slot early because doing so would violate connection
ownership.

`ConnectionSettings.commandTimeout` is independent of the pool timeout. It asks
PostgreSQL to cancel the active command; a pool execution timeout retires the
entire leased socket.

### Pool metrics

Metrics are read-only and do not open another connection:

| Metric | Meaning |
|---|---|
| `openConnectionCount` | Retained physical connections that are not closed |
| `leasedConnectionCount` | Slots currently owned by operations |
| `pendingOperationCount` | Operations waiting for a slot |
| `rejectedOperationCount` | Operations rejected because the FIFO was full |
| `queuedOperationTimeoutCount` | Accepted operations that timed out in the FIFO |
| `operationTimeoutCount` | Leased operations whose execution timer expired |
| `connectionReplacementCount` | Successful in-place replacements |
| `connectionReplacementFailureCount` | Failed replacement attempts |

`close()` stops accepting new operations and waits for already accepted work
before closing the physical connections.

## Date, timestamp, and IANA timezones

PostgreSQL `timestamptz` stores an instant, not an attached zone name. The
default `TimeZoneSettings.utc()` path returns that instant as a UTC `DateTime`.
It is exact and does not initialize timezone data.

Enable named IANA materialization only when the application needs the same
instant represented in a particular zone:

```dart
final settings = ConnectionSettings(
  user: 'dart',
  password: 'dart',
  database: 'postgres',
  timeZone: const TimeZoneSettings(
    'America/Sao_Paulo',
    forceDecodeTimestamptzAsUTC: false,
    useIanaTimeZoneDatabase: true,
    ianaTimeZoneDatabaseScope: PgTimeZoneDatabaseScope.latestAll,
  ),
);
```

`latestAll` contains full historical transitions and is the
correctness-oriented default for named zones. `latest10y` is regenerated for a
window from five years before through five years after the generator's current
year; use it only when the application's date range fits that window. Named
decoding returns a `TZDateTime` representing the same instant with the selected
historical offset.

If `forceDecodeTimestamptzAsUTC` is false but the IANA database is not enabled,
Dargres uses Dart's local operating-system timezone; `TimeZoneSettings.value`
does not select an arbitrary OS zone in that mode.

`forceDecodeTimestampAsUTC` and `forceDecodeDateAsUTC` control civil
`timestamp without time zone` and `date` materialization. PostgreSQL
`infinity` and `-infinity` decode to `null` by default; set
`throwOnDateTimeInfinity: true` to reject them.

`SET TIME ZONE` updates the server timezone used by both cold and cached result
schemas.

### Regenerating vendored IANA data

The generator is pure Dart. With no arguments it downloads current IANA data
and regenerates the compact ten-year file:

```powershell
dart run scripts/generate_pg_timezone_data.dart
```

Generate the full historical file with:

```powershell
dart run scripts/generate_pg_timezone_data.dart `
  --scope latest_all `
  --output lib/src/utils/pg_timezone/timezone/pg_timezone_data_all.dart
```

Use `--iana <file-or-directory>` for an already downloaded source and
`--iana-version <version>` for a pinned published version. Generated files are
versioned source files and should not be edited manually. See
[scripts/README.md](scripts/README.md) for the complete workflow.

## TLS

Supplying `sslContext` enables PostgreSQL TLS negotiation.

For platform-root certificate verification:

```dart
import 'dart:io';

import 'package:dargres/dargres.dart';

final roots = SecurityContext(withTrustedRoots: true);
final settings = ConnectionSettings(
  user: 'dart',
  password: 'dart',
  database: 'postgres',
  sslContext: SslContext(context: roots),
);
```

A custom `SecurityContext` can load private CA certificates before being passed
to `SslContext`. Leave `onBadCertificate` null when normal certificate
validation must reject an invalid peer.

Important: `SslContext.createDefaultContext()` is a compatibility helper whose
`onBadCertificate` callback accepts every certificate. Likewise, the current
`sslmode=require` URI path enables encryption without certificate identity
verification. Do not use either contract where server identity verification is
required; pass an explicit verified `SslContext` instead.

## Notices and notifications

`notices` and `notifications` are broadcast streams on a physical
`CoreConnection`. A notification event is currently a map with `backendPid`,
`channel`, and `payload` keys.

Use a dedicated connection for long-lived `LISTEN` subscriptions so ordinary
pool leases and application queries cannot delay notification handling:

```dart
final listener = CoreConnection(
  'dart',
  password: 'dart',
  database: 'postgres',
);

await listener.connect();
listener.notifications.listen(print);
await listener.execute('LISTEN job_events');
```

The streams close on terminal connection close.

## Tests and static analysis

Install development dependencies and run:

```powershell
dart pub get
dart analyze --fatal-infos
dart test test/unit
```

Most integration tests use `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, and
`PGPASSWORD`. Defaults are `localhost`, `5432`, `postgres`, `dart`, and
`dart`. The cancellation suite currently uses those defaults directly. The
query suite drops and recreates the `myschema` schema, so run integration tests
only against a development/test database where that schema is disposable:

```powershell
$env:PGHOST = 'localhost'
$env:PGPORT = '5432'
$env:PGDATABASE = 'postgres'
$env:PGUSER = 'dart'
$env:PGPASSWORD = 'dart'
$env:PGSSLMODE = 'disable'

dart test test/integration --concurrency=1
```

CI runs analysis, unit tests, and integration tests against PostgreSQL 17 on
Dart 3.6.0 and the current stable Dart SDK.

### Driver comparison benchmark

The isolated harness compares Dargres with the sibling `postgres_fork` checkout
using deterministic rows and checksums. That sibling is a mutable local path
dependency, so record its commit when producing results intended for later
comparison:

```powershell
cd benchmark/driver_comparison
dart pub get --offline
dart run bin/driver_comparison.dart --setup-only
dart run bin/driver_comparison.dart --output=results/comparison.json
```

It measures cold and warm map materialization, typed entities, and callback
aggregation. The checked-in local JIT and AOT runs report Dargres ahead in the
measured scenarios, but they describe one machine, schema, server state, and
driver pair; rerun the harness on representative production hardware.

- [Benchmark methodology](benchmark/driver_comparison/README.md)
- [Checked-in JIT result](benchmark/driver_comparison/results/comparison-rows10000-postfix.json)
- [Checked-in AOT result](benchmark/driver_comparison/results/comparison-rows10000-aot.json)

### Connection soak

The soak tool runs concurrent pool traffic, validates results, stops on the
first error, and reports throughput, pool counters, replacements, and RSS:

```powershell
dart run tool/connection_soak.dart `
  --duration-seconds=3600 `
  --pool-size=8 `
  --concurrency=32 `
  --timeout-seconds=30
```

Use longer runs and the same network, PostgreSQL settings, schema, and
deployment shape as production. A finite local soak is evidence for that
environment, not a guarantee of indefinite uptime.

### PostgreSQL restart fault test

On Windows, the destructive restart test interrupts in-flight commands, stops
PostgreSQL for three seconds, begins recovery while the service is unavailable,
checks that backend PIDs changed, and runs post-restart concurrent load:

```powershell
dart run tool/postgres_restart_fault_test.dart
```

Defaults:

- gsudo: `C:\gsudo\2.6.1\gsudo.exe`
- Windows service: `postgresql-x64-17`

Override them with `DARGRES_GSUDO` and `DARGRES_POSTGRES_SERVICE`. The tool also
uses the standard `PG*` connection variables. It requires permission to stop
the service and will interrupt every client using that PostgreSQL instance; run
it only against a disposable development/test server.

## Migrating to 4.0

Version 4.0 intentionally includes breaking API and ownership changes. In
particular:

- Dart 3.6 is the minimum SDK;
- runtime package dependencies were removed;
- `Row` values are `Object?`;
- the direct APIs use named `params` and explicit placeholder styles;
- `RowView` is ephemeral;
- prepared handles no longer carry mutable per-execution result state;
- `PostgreSqlPool` is an operation pool and no longer pretends to be a
  connection;
- unsafe pool timeout modes were removed.

See:

- [Performance API migration guide](PERFORMANCE_MIGRATION.md)
- [Changelog](CHANGELOG.md)
- [Refactoring plan and measured scope](PLANO_REFATORACAO_PERFORMANCE.md)

## Acknowledgements and license

Dargres began as a pure-Dart port inspired by Tony Locke's
[pg8000](https://github.com/tlocke/pg8000) and has drawn protocol and design
ideas from the wider open-source PostgreSQL driver ecosystem.

See [LICENSE](LICENSE) for the project license.
