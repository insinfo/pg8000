# Changelog

## 4.0.1

Details: [doc/release_notes_4.0.1.md](doc/release_notes_4.0.1.md).

### Fixed

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

### Added

- `searchPath` and `sessionStatements`, applied to every physical session
  (pool slots and reconnects included) before `connect()` completes.
- `client_encoding` (from `textCharset`) and `DateStyle=ISO` in the startup
  packet.
- Opt-in `numericAsString` for exact `numeric` values.
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
