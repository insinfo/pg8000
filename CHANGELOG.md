# Changelog

## 4.0.1

Details: [doc/release_notes_4.0.1.md](doc/release_notes_4.0.1.md).

### Fixed

- `money` (and `money[]`) is the exact decimal amount (`'1234.56'`,
  `'-0.05'`), as postgres_fork returns it. It was the lc_monetary text
  (`'R$ 1.234,56'`), with the currency symbol and the locale's separators.
- `float4` read in text (cold executions, simple protocol) gave the shortest
  decimal (`0.1`), and in binary (warm executions) the float4 value
  (`0.10000000149011612`), so the same query returned two different doubles.
  Text is now read as a float4 and widened, as the binary format; `float4[]`
  too.
- DateTime parameters carry their zone: a local DateTime was sent without its
  offset, so the server read it in the session time zone (a process in UTC
  with a session in America/Sao_Paulo stored timestamptz three hours off).

- Transaction commands (`COMMIT`, `ROLLBACK`, `SAVEPOINT`) could wait forever
  after the transaction awaited other I/O, e.g. a second pool lease.
- `PostgreSqlPool` opens connections on demand instead of all slots at once.
- Text `date`/`timestamp`/`timestamptz` decoding no longer depends on the OS
  time zone (DST-gap shift, BC dates and LMT offsets now match binary).
- `?` placeholders after a literal ending in `\` are rewritten correctly.
- Typo in the missing MD5 password error message.
- A query issued on a `CoreConnection` (not on the `TransactionContext`) while
  another caller's `runInTransaction` callback ran failed on the extended
  protocol (`queryNamed`, `queryUnnamed`, `queryMaps`, ...: "A transaction is
  active"); it now waits for the commit or rollback, as the simple protocol
  did. Issued from the callback itself, it runs in the transaction (it threw,
  or for `execute` waited forever). See `queueConcurrentCalls`.
- A queued transaction no longer runs ahead of queries that arrived before
  it, and a query that waited for another caller's preparation of the same
  statement keeps its place: queries and transactions run in arrival order.
- `runInTransaction`/`beginTransaction` from inside a `runInTransaction`
  callback fails with a `StateError` (it waited for itself forever).
- `COPY ... FROM STDIN` hung the connection, and every caller queued behind
  it, forever; it now fails with SQLSTATE 57014 (there is no COPY IN API).
- An unnamed prepared statement (`prepareStatement(isUnamedStatement: true)`)
  executed whatever statement was parsed unnamed last, e.g. any caller's
  `queryUnnamed`: silently wrong results. It is parsed again on execution.
- `CoreConnection.executeStatement(isDeallocate: true)` reported a failed
  execution as an uncaught asynchronous error.
- Text `float8` and `numeric` were not correctly rounded (`0.1 + 0.2` read as
  `0.3000000000000001`, the float8 maximum as `Infinity`, subnormals as `0`):
  a cold (text) and a warm (binary) execution of one statement returned
  different doubles.
- Array parameters: a `'null'` string element was sent as SQL NULL, and a
  NaN or infinite double element failed with 22P02.
- Multidimensional arrays, arrays with explicit bounds (`[0:1]={1,2}`) and
  `json[]`/`jsonb[]` with non-object elements failed to decode.
- `DateTime` parameters with a year before 1 (BC) or after 9999 were
  rejected by the server.
- `DEALLOCATE PREPARE ALL`, and `DEALLOCATE ALL`/`DISCARD ALL` after other
  statements of a simple query, left the statement cache stale: the next
  cached query failed with 26000.
- A query issued on the connection from a `runInTransaction` callback after
  the connection died under that transaction ran outside it, autocommitted
  on the reconnected session; it now fails with a `StateError`.
- With `textCharset: 'ascii'`, a non-ASCII NOTICE (any localized one),
  notification payload or ParameterStatus closed the connection.

### Added

- `searchPath` and `sessionStatements`, applied to every physical session
  (pool slots and reconnects included) before `connect()` completes.
- `client_encoding` (from `textCharset`) and `DateStyle=ISO` in the startup
  packet.
- Opt-in `numericAsString` for exact `numeric` values.
- `queueConcurrentCalls` (default `true`) on `ConnectionSettings` and
  `CoreConnection`; `false` makes queries from outside a running transaction
  fail instead of waiting.
- `repository` and `issue_tracker` in the pubspec.

## 4.0.0

Details: [doc/release_notes_4.0.0.md](doc/release_notes_4.0.0.md) and
[PERFORMANCE_MIGRATION.md](PERFORMANCE_MIGRATION.md).

High-performance rewrite: 2.0x–2.75x faster than `postgres_fork` in the
recorded 10,000-row benchmarks (JIT and AOT).

### Added

- Direct query APIs `queryMaps`, `queryTyped<T>`, `queryEach` and
  `queryCached`, with `RowView` and per-column `ResultSchema` decoders.
- Per-connection LRU prepared-statement cache (`statementCacheCapacity`).
- Selective binary result decoding, plus opt-in `requireBinaryResults`.
- Opt-in IANA time zone decoding.
- `ReconnectPolicy`, `ping()`/`checkHealth()`, command timeout with
  `CancelRequest`, and `cancelCurrentQuery()`.
- Bounded pool admission queue (`maxPendingOperations`,
  `PoolQueueFullException`) and pool metrics.
- Zero runtime dependencies (internal crypto, encodings and pool).

### Changed

- Cold queries send `Parse + Describe + Bind + Execute + Sync` in one batch;
  cache hits send only `Bind + Execute + Sync`.
- `PostgreSqlPool` leases one physical connection per operation/transaction and
  replaces sockets closed by timeouts.
- Hardened connect/reconnect/close, SCRAM and socket flushing.
- Minimum Dart SDK `^3.6.0`.

### Breaking changes

- `Row[]` returns `Object?`.
- The direct APIs take named parameters; `?` placeholders are never
  auto-detected.
- `RowView` is valid only inside its synchronous callback; `queryEach` does
  not await asynchronous callbacks.
- `PostgreSqlPool` no longer implements `ConnectionInterface`.
- `CoreConnection.close()` is terminal.
- Removed `QueryState`/`Query.state`, `PostgreSqlPool.restartOnTimeout` and
  transaction `timeoutInner`.

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
