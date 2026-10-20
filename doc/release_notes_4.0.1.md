# dargres 4.0.1 — detailed release notes

Summary in [CHANGELOG.md](../CHANGELOG.md#401).

This release came out of validating dargres as the driver of a large
application (via the `eloquent` query builder) against its full integration
suite and a value-by-value comparison with `postgres_fork` over ~189,000 real
cells. Every item below was reproduced first and is covered by a regression
test.

## Fixed

### COMMIT (or any transaction command) could wait forever

`TransactionContext.execute` — used for `BEGIN`, `COMMIT`, `ROLLBACK` and
`SAVEPOINT` — only appended the command to the transaction queue. The send loop
was woken by the `Timer.run` that the *previous* command scheduled on
ReadyForQuery. If the transaction callback awaited real I/O between two
commands (a timer, a file, a query on another connection, or another pool
lease), that wake-up had already run with an empty queue, and the command was
never sent.

Typical symptoms:

- a pool transaction that used a second pooled connection never committed and
  ended in `TimeoutException: PostgreSQL pool operation timed out`;
- a transaction that generated a file between two statements hung on commit.

The transaction queue now calls `CoreConnection.scheduleQueuedQueries()` after
queuing a command. Tests: `test/integration/transaction_test.dart`.

### Pool opened every slot on first use

`PostgreSqlPool` used to open all `size` sockets the first time it was used.
An application that creates several pools (one per process, worker or test
setup) therefore used `size` server connections per pool even when the work was
sequential, and reached `53300 too many clients` on servers with the default
`max_connections = 100`.

Slots now start empty. A lease prefers an idle open connection (which also
keeps the statement cache warm) and only opens a socket for an empty slot when
every open one is busy. The socket is opened outside the lease mutex after the
slot is reserved, so other leases are not blocked by a connect. Test:
`opens sockets on demand and reuses an idle one` in
`test/integration/pool_test.dart`.

### Text date/time decoding depended on the client OS time zone

The cold path of every statement-cache miss receives text results. `date`,
`timestamp` and `timestamptz` were parsed with `DateTime.tryParse`, which
builds a **local** `DateTime` before the components were copied. Consequences,
all observed on real data:

| Value | Before (cold path) | Binary path / now |
|---|---|---|
| `timestamp '2003-11-04 00:00'` with OS zone `America/Sao_Paulo` (DST started at 00:00) | `2003-11-04 01:00` | `2003-11-04 00:00` |
| `date '0001-01-01 BC'` | `null` | `0000-01-01` (astronomical year) |
| `timestamptz '1900-01-01 00:00-03:06:28'` (local mean time) | `null` | `1900-01-01 03:06:28Z` |

The values are now parsed component by component from the ISO text
(`YYYY-MM-DD[ HH:MM:SS[.ffffff][±HH[:MM[:SS]]]][ BC]`, years with 4+ digits),
without any local `DateTime`. Text and binary results are identical. Tests:
`test/unit/datetime_text_test.dart` and the cold/warm comparison in
`test/integration/session_test.dart`.

### `?` after a literal ending in a backslash was not rewritten

With `standard_conforming_strings = on` (the default since PostgreSQL 9.1), a
backslash is an ordinary character in `'...'`. The placeholder rewriter treated
it as an escape, so in `select 'C:\' caminho, ? p` the literal never closed and
`?` stayed in the SQL (`42703 column "p" does not exist`). Backslash escapes are
now honoured only in `E'...'` literals, or for every literal when the server
reports `standard_conforming_strings = off`.

### Error message

The missing MD5 password error had a double space ("no password  was
provided"), which also failed an existing integration test.

## Added

### Session initialization: `searchPath` and `sessionStatements`

```dart
final settings = ConnectionSettings(
  user: 'app',
  database: 'db',
  searchPath: '"public","protocolo"',
  sessionStatements: ["SET statement_timeout = '30s'"],
);
```

Both run on **every physical session**: right after authentication, again after
each reconnect, and for every pool slot, including replacements. The SQL is
queued ahead of anything queued while connecting, and `connect()` only
completes after it succeeds. A transaction requested meanwhile starts only
afterwards. If it fails, the socket is closed and `connect()` throws, so a
session without its `search_path` is never used.

`SET` is used instead of startup parameters on purpose: PgBouncer rejects
unknown startup parameters such as `search_path`.

### Startup parameters

- `client_encoding` now follows `textCharset` (`utf8` → `UTF8`, `latin1` /
  `iso-8859-1` → `LATIN1`, `win1252` → `WIN1252`). Before, the server default
  (the database encoding) was used while dargres decoded with `textCharset`,
  which garbled text when the two differed.
- `DateStyle=ISO`, the format the text decoders expect. Only the output style
  is set; the server's day/month input order is unchanged.

### `numericAsString`

`numeric` is decoded to `double` by default, which loses digits beyond about
15 significant digits (`12345678901234567.89` → `12345678901234568.0`) and
the scale (`150.50` → `150.5`). With `numericAsString: true` (on
`ConnectionSettings` or `CoreConnection`) the exact server text is returned,
as `postgres`/`postgres_fork` do; `numeric[]` becomes `List<String?>`. The
default is unchanged.

### Concurrent callers of one connection: `queueConcurrentCalls`

One `CoreConnection` shared by concurrent callers (an HTTP server with a
single connection, for example) queues their queries. During a
`runInTransaction` callback:

| Query issued | 4.0.0 | 4.0.1 |
|---|---|---|
| on the connection, by another caller, simple protocol (`execute`, `querySimple`) | waited for the transaction | same |
| on the connection, by another caller, extended protocol (`queryNamed`, `queryUnnamed`, `queryMaps`, ...) | `StateError` "A transaction is active" | waits for the commit or rollback |
| on the connection, from the callback (instead of the `TransactionContext`) | `StateError`, or waited forever (`execute`) | runs in the transaction |
| `runInTransaction` / `beginTransaction` from the callback | waited forever | `StateError` |

The callback is recognized through a `Zone` value, so queries from anything
it starts (`Future.wait`, timers) belong to the transaction too. Do not wait,
inside the callback, for work started outside it that uses the same
connection: that work waits for the transaction, which waits for it.

Queries and transactions run in arrival order: a transaction queued behind
another one no longer runs ahead of queries that arrived before it (under
constant transactional load those could wait indefinitely).

During a transaction opened with `beginTransaction()` (no callback), dargres
cannot tell its owner from other callers: extended-protocol queries on the
connection still fail, simple-protocol ones still wait.

With `queueConcurrentCalls: false`, queries on the connection from outside a
running transaction fail with a `StateError` instead of waiting (simple
protocol included), which shows a connection shared by mistake. Queries
outside transactions are queued either way, as before. A pool lends each
connection to one caller at a time, so this changes nothing for it.

## Known differences from `postgres_fork` (unchanged)

- Arrays decode to nullable element lists (`List<int?>`, `List<String?>`);
  `List<int>.from(...)` works, a direct `as List<int>` cast does not.
- `interval` and `time` are returned as `String` (`postgres_fork` returns
  `Duration` for intervals without days/months and raw bytes for `time`).
- `inet` is returned as its text form (`postgres_fork` returns raw bytes).
