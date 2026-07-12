# Changelog

## 4.0.0

### Added

- Added direct extended-protocol APIs on connection, transaction, and pool
  surfaces:
  - `queryMaps` returns one stable `Map<String, dynamic>` per row without an
    intermediate `Row` or stream event.
  - `queryTyped<T>` maps a reused, ephemeral `RowView` directly to application
    entities.
  - `queryEach` consumes rows through a synchronous callback without retaining
    a driver result list.
  - `queryCached` keeps the compatible `Results`/`Row` result shape while using
    the direct decoder and statement cache.
- Added `RowView` typed accessors and `ResultSchema` with decoders resolved once
  per result column.
- Added a bounded per-physical-connection LRU prepared-statement cache for the
  direct APIs. `statementCacheCapacity` is available on `CoreConnection` and
  `ConnectionSettings`, defaults to `64`, and uses `0` to disable retention.
  Cache length and hit/miss/eviction counters are exposed for diagnostics.
- Added selective binary result decoding for supported scalar OIDs, with text
  fallback for unsupported columns. Parameters remain text-encoded.
- Added opt-in `requireBinaryResults` to the four direct APIs on connections,
  transactions, and pools. It requests binary for every result column and
  fails on an unsupported OID; strict failures never retry the SQL and cannot
  duplicate side effects. The safe selective/text-fallback mode remains the
  default.
- Added internal MD5, SHA-1, SHA-256, HMAC, PBKDF2, hexadecimal, Windows-1252
  and bounded FIFO pool implementations, leaving zero runtime package
  dependencies.
- Added opt-in named IANA timezone decoding with full-history and compact
  generated databases. UTC remains the allocation-minimal default.
- Added separate `test/unit` and `test/integration` suites and PostgreSQL 17 CI
  using `localhost:5432`, database `postgres`, and `dart`/`dart` credentials.
- Added a reproducible JIT/AOT comparison harness and a configurable
  connection/pool soak tool with throughput, queue, connection, error, and RSS
  reporting.
- Added `ReconnectPolicy` with bounded exponential backoff and jitter, plus
  explicit `ping()`/`checkHealth()` APIs.
- Added a configurable command timeout, PostgreSQL wire-level
  `CancelRequest`, configurable cancellation grace period, and
  `cancelCurrentQuery()` for direct connections.
- Added a bounded pool admission queue (`maxPendingOperations`),
  `PoolQueueFullException`, and rejection/timeout/replacement metrics.
- Added the pure-Dart IANA generator under `scripts/` and a Windows PostgreSQL
  restart fault test using `gsudo`.
- Validated the release with 326 unit tests, 71 PostgreSQL integration tests,
  a real three-second PostgreSQL service outage/recovery, and a 60-second soak
  of 1,346,073 operations with zero errors.

### Changed

- By default, cold direct queries use one
  `Parse + Describe + Bind + Execute + Sync` protocol batch and text results.
  Warm cache hits reuse statement/schema metadata, send
  `Bind + Execute + Sync`, and request binary per supported result column.
  Opt-in strict mode requests binary for every column on both paths.
- Data rows are decoded directly from byte ranges. The typed/callback paths
  reuse one value buffer, while the map and compatibility paths materialize
  only their documented final result objects.
- Prepared-statement executions now use independent per-execution state rather
  than reusing a stream controller, counters, and errors from the prepared
  `Query` handle.
- `Row` is now `ListBase<Object?>`; indexed values and `toList()` are explicitly
  nullable-object typed.
- Enabling `tcpKeepalive` now applies the socket keepalive option.
- `PostgreSqlPool` now leases a distinct physical connection for an entire
  operation/transaction and replaces sockets closed by timeouts.
- Concurrent `connect()` and reconnect calls now coalesce through
  authentication; terminal `close()` invalidates pending opens so an older
  socket cannot resurrect the connection.
- A pool timeout now quarantines its lease until the underlying Future settles,
  then replaces the socket in the same slot before reuse.
- Cached date/timestamp decoders now observe `SET TIME ZONE` changes without
  rebuilding the prepared-statement schema.
- Authentication `ErrorResponse` parsing now tolerates diagnostics received
  before `client_encoding` is applied and always completes a failed connect.
- SCRAM now requires a configured password, selects the supported
  `SCRAM-SHA-256` mechanism explicitly, and reports configuration errors
  without leaking a null-check or a second uncaught Zone error.
- Removed unawaited `Socket.flush()` calls from startup, SCRAM, and normal
  query writes. They could race the next `Socket.add()` and intermittently
  raise `StreamSink is bound to a stream`; the terminal flush is awaited.
- The minimum Dart SDK is now `^3.6.0`.

### Removed

- Removed the direct runtime dependencies on `crypto`, `convert`, `collection`,
  `enough_convert`, `pool`, and `path`.
- Removed the Terrier/ISOOS/queue buffers, pack/unpack alternatives, experiments,
  commented pool implementation, unused executor/retry/stack-trace copies,
  dead converters/utilities and obsolete benchmark scripts.
- Removed the old uninitialized timezone branch; named-zone behavior is now the
  explicit generated-IANA path.
- Removed `PostgreSqlPool.restartOnTimeout` and transaction `timeoutInner`; both
  allowed unsafe or ambiguous timeout ownership.

### Breaking changes and migration notes

- `Row.operator []` now returns `Object?` instead of `dynamic`. Existing code
  may need an explicit cast, for example `row[0] as int`.
- Parameters on the four direct query APIs are now named. They accept explicit
  PostgreSQL `$n`, question-mark, colon and at-sign placeholder styles; `?` is
  never auto-detected. Use `List` for `$n`/`?`, `Map` for `:`/`@`, and retain
  the default `$n` style when SQL contains PostgreSQL JSON `?` operators.
- A `RowView` and its `values` list are valid only inside the synchronous
  mapper/callback. Copy data or construct an owned entity before returning; do
  not retain the view.
- `queryEach` does not await asynchronous callbacks.
- A prepared `Query` is statement metadata, not the observable state of its
  most recent execution. Read rows, affected counts, and errors from the
  returned `Results`/`ResultStream` instead.
- `QueryState`/`Query.state` were removed because no protocol decision consumed
  them.
- `PostgreSqlPool` no longer implements `ConnectionInterface`; connection-like
  methods that threw `UnimplementedError` or leaked prepared handles outside a
  lease were removed. Use `runInTransaction` and the materialized/direct query
  APIs.
- `queryCached` caches prepared-statement metadata, never result rows. The cache
  is local to a physical connection, so pooled connections warm independently.
- Direct command timeouts are opt-in so the default hot path does not allocate
  a Dart `Timer` for every query.
- `CoreConnection.close()` is terminal. Create a new connection object after an
  intentional close; automatic reconnect remains available only after a
  recoverable socket failure.
- Pool overload above `maxPendingOperations` is rejected instead of queued
  indefinitely.

See `PERFORMANCE_MIGRATION.md` for before/after examples and cache lifecycle
guidance. In the recorded 10,000-row run, dargres beat the pinned
`postgres_fork` in all six measured scenarios after lifecycle hardening:
2.13x-2.75x on JIT and 2.02x-2.66x on AOT. Raw reports are under
`benchmark/driver_comparison/results/`.

## 3.1.2

- Fixed the default `Location` initialization to use UTC.

## 3.1.1

- Added flags to `TimeZoneSettings` for more flexible decoding of `date`,
  `timestamp`, and `timestamptz` values.

## 3.1.0

- **Breaking change:** decoded `timestamp without time zone` as a local
  `DateTime` and decoded `timestamp with time zone` using the timezone defined
  on the connection.

## 3.0.2

- Fixed setting `application_name` on PostgreSQL versions earlier than 8.2.

## 3.0.1

- Fixed a critical stack-overflow bug introduced in 3.0.0. Timeout parameters
  were removed from query execution methods such as `queryNamed`,
  `queryUnnamed`, `querySimple`, `execute`, `prepareStatement`, and
  `executeStatement`.

## 3.0.0

- Implemented `PostgreSqlPool` with optional automatic reconnect after a
  connection drop.

```dart
final settings = ConnectionSettings(
  user: 'user',
  database: 'database',
  host: 'localhost',
  port: 5433,
  password: 'password',
  textCharset: 'latin1',
  applicationName: 'dargres',
);
final conn = PostgreSqlPool(
  2,
  settings,
  allowAttemptToReconnect: true,
);
```

## 2.2.4

- Added Windows-1252 (`win1252`) support to `CoreConnection`.

```dart
final con = CoreConnection(
  'user',
  database: 'db',
  host: 'localhost',
  port: 5432,
  password: 'pass',
  textCharset: 'win1252',
);
```

## 2.2.3

- Fixed a serious intermittent error when executing prepared statements for
  `SELECT` queries that return large amounts of data.

## 2.2.2

- Fixed query-error and database-restart handling bugs.

## 2.2.1

- Fixed bugs in `queryUnnamed` and `prepareStatement`.

## 2.2.0

- Implemented `ResultStream` and `Results` for data returned by
  `queryUnnamed` and `querySimple`.

## 2.1.0

- Added placeholder-style selection to `queryUnnamed` and
  `prepareStatement`, including PHP PDO-style question-mark parameters.

```dart
queryUnnamed(
  'SELECT * FROM book WHERE title = ? AND code = ?',
  ['title', 10],
  placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
);
```

## 2.0.0

- Migrated the package to null safety.

## 1.0.1

- Fixed an insert bug and implemented `queryUnnamed` for unnamed prepared
  statement execution.

## 1.0.0

- Initial version.
