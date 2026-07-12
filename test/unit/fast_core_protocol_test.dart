import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dargres/dargres.dart';
import 'package:dargres/src/connection_state.dart';
import 'package:dargres/src/fast/pg_write_buffer.dart';
import 'package:test/test.dart';

void main() {
  group('CoreConnection fast protocol', () {
    late ServerSocket server;
    late Socket backend;
    late _SocketReader reader;
    late CoreConnection connection;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = server.first;
      connection = CoreConnection(
        'test_user',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        database: 'test_database',
        statementCacheCapacity: 2,
      );

      final connected = connection.connect();
      backend = await accepted;
      reader = _SocketReader(backend);
      final startup = await reader.readStartup();
      expect(_containsCString(startup, 'test_user'), isTrue);
      expect(_containsCString(startup, 'test_database'), isTrue);

      final auth = PgWriteBuffer();
      _message(auth, 0x52, () => auth.writeInt32(0)); // AuthenticationOk
      _message(auth, 0x53, () {
        auth.writeBytes(ascii.encode('integer_datetimes'));
        auth.writeUint8(0);
        auth.writeBytes(ascii.encode('on'));
        auth.writeUint8(0);
      });
      _message(auth, 0x5a, () => auth.writeUint8(0x49)); // Ready/idle
      backend.add(auth.toBytes());
      await backend.flush();
      await connected.timeout(const Duration(seconds: 5));
    });

    tearDown(() async {
      await connection.close();
      backend.destroy();
      await server.close();
    });

    test('cold text and warm binary paths feed every direct result API',
        () async {
      const sql = 'SELECT 42 AS id, \'hello\' AS name, true AS active';

      final coldFuture = connection.queryMaps(sql);
      final cold = await reader.readMessages(5);
      expect(cold.map((message) => message.code),
          <int>[0x50, 0x44, 0x42, 0x45, 0x53]); // P,D,B,E,S
      expect(_bindResultFormats(cold[2].body), isEmpty);
      await _respondSelect(backend,
          includeDescription: true, binary: false, fragmented: true);
      expect(await coldFuture, <Map<String, dynamic>>[
        <String, dynamic>{'id': 42, 'name': 'hello', 'active': true}
      ]);

      final warmFuture = connection.queryMaps(sql);
      final warm = await reader.readMessages(3);
      expect(warm.map((message) => message.code), <int>[0x42, 0x45, 0x53]);
      expect(_bindResultFormats(warm[0].body), <int>[1]);
      await _respondSelect(backend, includeDescription: false, binary: true);
      expect(await warmFuture, <Map<String, dynamic>>[
        <String, dynamic>{'id': 42, 'name': 'hello', 'active': true}
      ]);

      final typedFuture = connection.queryTyped<_Person>(
          sql,
          (row) => _Person(row.getInt('id')!, row.getString(1)!,
              row.getBoolByName('active')!));
      final typedMessages = await reader.readMessages(3);
      expect(_bindResultFormats(typedMessages[0].body), <int>[1]);
      await _respondSelect(backend, includeDescription: false, binary: true);
      expect(await typedFuture, <_Person>[const _Person(42, 'hello', true)]);

      var checksum = 0;
      final eachFuture = connection.queryEach(sql, (row) {
        checksum += row.getInt(0)!;
        expect(row.getStringByName('name'), 'hello');
      });
      await reader.readMessages(3);
      await _respondSelect(backend,
          includeDescription: false, binary: true, rowCount: 2);
      await eachFuture;
      expect(checksum, 84);

      final cachedFuture = connection.queryCached(sql);
      await reader.readMessages(3);
      await _respondSelect(backend, includeDescription: false, binary: true);
      final cached = await cachedFuture;
      expect(cached.single.toColumnMap(),
          <String, dynamic>{'id': 42, 'name': 'hello', 'active': true});

      expect(connection.statementCacheMisses, 1);
      expect(connection.statementCacheHits, 4);
      expect(connection.statementCacheLength, 1);
    });

    test('strict binary requests and decodes binary on the cold wire',
        () async {
      const sql =
          'SELECT 42 AS id, \'hello\' AS name, true AS active /* strict */';

      final selected = connection.queryMaps(sql, requireBinaryResults: true);
      final messages = await reader.readMessages(5);
      expect(messages.map((message) => message.code),
          <int>[0x50, 0x44, 0x42, 0x45, 0x53]);
      expect(_bindResultFormats(messages[2].body), <int>[1],
          reason: 'A single binary format applies to every result column.');

      await _respondSelect(backend,
          includeDescription: true,
          binary: true,
          descriptionBinary: false);
      expect(await selected, <Map<String, dynamic>>[
        <String, dynamic>{'id': 42, 'name': 'hello', 'active': true}
      ]);
    });

    test(
        'strict unsupported schema drains without retry and cache hit fails before wire',
        () async {
      const sql = 'SELECT extension_value /* strict unsupported */';

      var sinkCalls = 0;
      final failed = connection.executeDirect(
        sql,
        const <Object?>[],
        (query) {
          query.dataRowSink = (_, __, ___) => sinkCalls++;
        },
        requireBinaryResults: true,
      );
      final failedExpectation = expectLater(
          failed,
          throwsA(isA<UnsupportedError>()
              .having((error) => error.message, 'message', contains('900001'))
              .having((error) => error.message, 'message',
                  contains('complete binary decoders'))));
      final cold = await reader.readMessages(5);
      expect(cold.map((message) => message.code),
          <int>[0x50, 0x44, 0x42, 0x45, 0x53]);
      expect(_bindResultFormats(cold[2].body), <int>[1]);
      await _respondOneColumnSelect(backend,
          includeDescription: true,
          oid: 900001,
          value: ascii.encode('extension'));
      await failedExpectation;
      expect(sinkCalls, 0,
          reason: 'Rows must be drained without invoking the user sink.');
      expect(connection.statementCacheLength, 1,
          reason: 'Safe mixed-format metadata remains cacheable.');

      // This strict cache hit must fail before Bind is written. The next bytes
      // read below therefore belong to the safe mixed-format execution.
      final cachedStrict = connection.executeDirect(
        sql,
        const <Object?>[],
        (_) {},
        requireBinaryResults: true,
      );
      await expectLater(cachedStrict, throwsA(isA<UnsupportedError>()));

      final safe = connection.queryMaps(sql);
      final safeMessages = await reader.readMessages(3);
      expect(safeMessages.map((message) => message.code),
          <int>[0x42, 0x45, 0x53]);
      expect(_bindResultFormats(safeMessages[0].body), isEmpty);
      await _respondOneColumnSelect(backend,
          includeDescription: false,
          oid: 900001,
          value: ascii.encode('extension'));
      expect(await safe, <Map<String, dynamic>>[
        <String, dynamic>{'extension_value': 'extension'}
      ]);
    });

    test('question-mark placeholders are explicit across every fast API',
        () async {
      const sql =
          "SELECT ?::int4 AS id, 'hello' AS name, true AS active";
      const postgresSql =
          r"SELECT $1::int4 AS id, 'hello' AS name, true AS active";
      const params = <Object?>[42];

      final mapsFuture = connection.queryMaps(
        sql,
        params: params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      final cold = await reader.readMessages(5);
      expect(cold.map((message) => message.code),
          <int>[0x50, 0x44, 0x42, 0x45, 0x53]);
      expect(_parseSql(cold[0].body), postgresSql);
      await _respondSelect(backend, includeDescription: true, binary: false);
      expect((await mapsFuture).single['id'], 42);

      final typedFuture = connection.queryTyped<int>(
        sql,
        (row) => row.getInt('id')!,
        params: params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      expect((await reader.readMessages(3)).map((message) => message.code),
          <int>[0x42, 0x45, 0x53]);
      await _respondSelect(backend, includeDescription: false, binary: true);
      expect(await typedFuture, <int>[42]);

      var eachValue = 0;
      final eachFuture = connection.queryEach(
        sql,
        (row) => eachValue = row.getInt(0)!,
        params: params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      expect((await reader.readMessages(3)).map((message) => message.code),
          <int>[0x42, 0x45, 0x53]);
      await _respondSelect(backend, includeDescription: false, binary: true);
      await eachFuture;
      expect(eachValue, 42);

      final cachedFuture = connection.queryCached(
        sql,
        params: params,
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      expect((await reader.readMessages(3)).map((message) => message.code),
          <int>[0x42, 0x45, 0x53]);
      await _respondSelect(backend, includeDescription: false, binary: true);
      expect((await cachedFuture).single.toColumnMap()['id'], 42);

      const literalSql =
          "SELECT '?' AS marker, 42 AS id, 'hello' AS name, true AS active";
      final literalFuture = connection.queryMaps(literalSql);
      final literalMessages = await reader.readMessages(5);
      expect(_parseSql(literalMessages[0].body), literalSql,
          reason: 'pgDefault must not interpret question marks.');
      await _respondSelect(backend, includeDescription: true, binary: false);
      await literalFuture;
    });

    test('callback errors drain to ReadyForQuery and keep connection usable',
        () async {
      const sql = 'SELECT 42 AS id, \'hello\' AS name, true AS active';

      final seed = connection.queryMaps(sql);
      await reader.readMessages(5);
      await _respondSelect(backend, includeDescription: true, binary: false);
      await seed;

      final failed = connection.queryEach(sql, (_) {
        throw StateError('mapper failed');
      });
      final failedExpectation = expectLater(failed, throwsA(isA<StateError>()));
      await reader.readMessages(3);
      await _respondSelect(backend,
          includeDescription: false, binary: true, rowCount: 2);
      await failedExpectation;

      final afterFailure = connection.queryMaps(sql);
      await reader.readMessages(3);
      await _respondSelect(backend, includeDescription: false, binary: true);
      expect((await afterFailure).single['id'], 42);
    });

    test('transaction direct queries use the transaction queue and cache',
        () async {
      final begin = connection.beginTransaction();
      final beginMessage = (await reader.readMessages(1)).single;
      expect(beginMessage.code, 0x51);
      expect(_readCString(beginMessage.body, 0).value, 'BEGIN');
      await _respondCommand(backend, 'BEGIN', 0x54); // in transaction
      final transaction = await begin;

      const sql =
          "SELECT ?::int4 AS id, 'hello' AS name, true AS active";
      const postgresSql =
          r"SELECT $1::int4 AS id, 'hello' AS name, true AS active";
      final selected = transaction.queryMaps(
        sql,
        params: const <Object?>[42],
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      final selectedMessages = await reader.readMessages(5);
      expect(_parseSql(selectedMessages[0].body), postgresSql);
      await _respondSelect(backend,
          includeDescription: true, binary: false, transactionStatus: 0x54);
      expect((await selected).single['name'], 'hello');

      final commit = connection.commit(transaction);
      final commitMessage = (await reader.readMessages(1)).single;
      expect(commitMessage.code, 0x51);
      expect(_readCString(commitMessage.body, 0).value, 'COMMIT');
      await _respondCommand(backend, 'COMMIT', 0x49);
      await commit;
    });

    test('parameter encoding failures fail only that query', () async {
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;
      final invalid = connection.queryMaps('SELECT \$1::jsonb',
          params: <Object?>[cyclic]);
      await expectLater(invalid, throwsA(anything));

      const sql = 'SELECT 42 AS id, \'hello\' AS name, true AS active';
      final valid = connection.queryMaps(sql);
      final messages = await reader.readMessages(5);
      expect(messages.map((message) => message.code),
          <int>[0x50, 0x44, 0x42, 0x45, 0x53]);
      await _respondSelect(backend, includeDescription: true, binary: false);
      expect((await valid).single['id'], 42);
    });

    test('queryUnnamed always uses one-round-trip unnamed extended protocol',
        () async {
      const sql = 'SELECT 42 AS id, \'hello\' AS name, true AS active';

      for (var execution = 0; execution < 2; execution++) {
        final result = connection.queryUnnamed(sql, const <Object?>[]);
        final messages = await reader.readMessages(5);

        expect(messages.map((message) => message.code),
            <int>[0x50, 0x44, 0x42, 0x45, 0x53]);
        expect(_readCString(messages[0].body, 0).value, isEmpty,
            reason: 'Parse must target the unnamed statement.');
        final portal = _readCString(messages[2].body, 0);
        expect(portal.value, isEmpty);
        expect(_readCString(messages[2].body, portal.nextOffset).value, isEmpty,
            reason: 'Bind must target the unnamed statement.');

        await _respondSelect(backend, includeDescription: true, binary: false);
        expect((await result).single.toColumnMap()['id'], 42);
        expect(connection.statementCacheLength, 0);
        expect(connection.statementCacheHits, 0);
      }
    });

    test('eviction defers Close while the evicted statement is retained',
        () async {
      const sqlA =
          'SELECT 42 AS id, \'hello\' AS name, true AS active /* A */';
      const sqlB =
          'SELECT 42 AS id, \'hello\' AS name, true AS active /* B */';
      const sqlC =
          'SELECT 42 AS id, \'hello\' AS name, true AS active /* C */';

      final seedA = connection.queryMaps(sqlA);
      final seedAMessages = await reader.readMessages(5);
      final statementA = _readCString(seedAMessages[0].body, 0).value;
      await _respondSelect(backend, includeDescription: true, binary: false);
      await seedA;

      final seedB = connection.queryMaps(sqlB);
      final seedBMessages = await reader.readMessages(5);
      final statementB = _readCString(seedBMessages[0].body, 0).value;
      await _respondSelect(backend, includeDescription: true, binary: false);
      await seedB;
      expect(statementA, isNotEmpty);
      expect(statementB, isNotEmpty);
      expect(statementB, isNot(statementA));

      // C is executing while cached B and A are retained by queued hits. When
      // C is stored it evicts B, but B must remain usable until its queued hit
      // releases the statement reference.
      final coldC = connection.queryMaps(sqlC);
      await reader.readMessages(5);
      final retainedB = connection.queryMaps(sqlB);
      final retainedA = connection.queryMaps(sqlA);
      await _respondSelect(backend, includeDescription: true, binary: false);
      await coldC;

      final executeB = await reader.readMessages(3);
      expect(executeB.map((message) => message.code), <int>[0x42, 0x45, 0x53],
          reason: 'Close for B must remain deferred while B is retained.');
      final bPortal = _readCString(executeB[0].body, 0);
      expect(_readCString(executeB[0].body, bPortal.nextOffset).value,
          statementB);
      await _respondSelect(backend, includeDescription: false, binary: true);
      await retainedB;

      // Releasing B promotes its deferred Close into the next atomic batch.
      final executeA = await reader.readMessages(4);
      expect(executeA.map((message) => message.code),
          <int>[0x43, 0x42, 0x45, 0x53]);
      expect(executeA[0].body[0], 0x53); // Close target: statement.
      expect(_readCString(executeA[0].body, 1).value, statementB);
      final aPortal = _readCString(executeA[1].body, 0);
      expect(
          _readCString(executeA[1].body, aPortal.nextOffset).value, statementA);
      await _respondSelect(backend,
          includeDescription: false,
          binary: true,
          closeCompleteCount: 1);
      await retainedA;

      expect(connection.statementCacheEvictions, 1);
      expect(connection.statementCacheLength, 2);
    });

    test('maintenance Close error drains and retries the attached query',
        () async {
      const cachedSql =
          'SELECT 42 AS id, \'hello\' AS name, true AS active /* cached */';
      const retriedSql =
          'SELECT 42 AS id, \'hello\' AS name, true AS active /* retry */';

      final seed = connection.queryMaps(cachedSql);
      await reader.readMessages(5);
      await _respondSelect(backend, includeDescription: true, binary: false);
      await seed;
      connection.clearStatementCache();

      final retried = connection.queryMaps(retriedSql);
      final firstAttempt = await reader.readMessages(6);
      expect(firstAttempt.map((message) => message.code),
          <int>[0x43, 0x50, 0x44, 0x42, 0x45, 0x53]);

      // PostgreSQL ignores the rest of the batch after an error and resumes at
      // Sync/ReadyForQuery. The driver must not attribute this maintenance
      // failure to the user query.
      await _respondErrorAndReady(backend,
          code: '26000', message: 'prepared statement does not exist');

      final secondAttempt = await reader.readMessages(5);
      expect(secondAttempt.map((message) => message.code),
          <int>[0x50, 0x44, 0x42, 0x45, 0x53]);
      await _respondSelect(backend, includeDescription: true, binary: false);
      expect((await retried).single['id'], 42);
    });

    test('two concurrent transactions are serialized through commit',
        () async {
      var secondBegan = false;
      final firstFuture = connection.beginTransaction();
      final secondFuture = connection.beginTransaction().then((transaction) {
        secondBegan = true;
        return transaction;
      });

      final firstBegin = (await reader.readMessages(1)).single;
      expect(firstBegin.code, 0x51);
      expect(_readCString(firstBegin.body, 0).value, 'BEGIN');
      await _respondCommand(backend, 'BEGIN', 0x54);
      final first = await firstFuture;
      await Future<void>.delayed(Duration.zero);
      expect(secondBegan, isFalse);

      const sql = 'SELECT 42 AS id, \'hello\' AS name, true AS active';
      final selected = first.queryMaps(sql);
      await reader.readMessages(5);
      await _respondSelect(backend,
          includeDescription: true, binary: false, transactionStatus: 0x54);
      expect((await selected).single['active'], isTrue);

      final firstCommit = connection.commit(first);
      final commitMessage = (await reader.readMessages(1)).single;
      expect(commitMessage.code, 0x51);
      expect(_readCString(commitMessage.body, 0).value, 'COMMIT');
      await _respondCommand(backend, 'COMMIT', 0x49);
      await firstCommit;

      final secondBegin = (await reader.readMessages(1)).single;
      expect(secondBegin.code, 0x51);
      expect(_readCString(secondBegin.body, 0).value, 'BEGIN');
      await _respondCommand(backend, 'BEGIN', 0x54);
      final second = await secondFuture;

      final secondCommit = connection.commit(second);
      final secondCommitMessage = (await reader.readMessages(1)).single;
      expect(secondCommitMessage.code, 0x51);
      expect(_readCString(secondCommitMessage.body, 0).value, 'COMMIT');
      await _respondCommand(backend, 'COMMIT', 0x49);
      await secondCommit;
    });
  }, timeout: const Timeout(Duration(seconds: 20)));

  group('CoreConnection lifecycle', () {
    test('coalesces connect through startup authentication', () async {
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<Socket>();
      var acceptedCount = 0;
      final serverSubscription = server.listen((socket) {
        acceptedCount++;
        if (!accepted.isCompleted) accepted.complete(socket);
      });
      final connection = CoreConnection(
        'test_user',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        database: 'test_database',
      );
      addTearDown(() async {
        await connection.close();
        await serverSubscription.cancel();
        await server.close();
      });

      final connectedBeforeOpen = connection.whenConnected;
      final first = connection.connect();
      final backend = await accepted.future;
      addTearDown(backend.destroy);
      await _SocketReader(backend).readStartup();

      final second = connection.connect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(acceptedCount, 1,
          reason: 'SCRAM/startup must remain one coalesced open operation.');

      await _respondAuthenticationOk(backend);
      final connected = await Future.wait(<Future<CoreConnection>>[
        connectedBeforeOpen,
        first,
        second,
      ]);
      expect(identical(connected[0], connection), isTrue);
      expect(identical(connected[1], connection), isTrue);
      expect(identical(connected[2], connection), isTrue);
      expect(acceptedCount, 1);
    });

    test('close during authentication cannot resurrect the socket', () async {
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = server.first;
      final connection = CoreConnection(
        'test_user',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        database: 'test_database',
        allowAttemptToReconnect: true,
      );
      addTearDown(() async {
        await connection.close();
        await server.close();
      });
      final noticesDone = connection.notices.drain<void>();
      final notificationsDone = connection.notifications.drain<void>();

      final opening = connection.connect();
      final openingFailed =
          expectLater(opening, throwsA(isA<PostgresqlException>()));
      final backend = await accepted;
      addTearDown(backend.destroy);
      await _SocketReader(backend).readStartup();

      await connection.close();
      await openingFailed;
      await noticesDone.timeout(const Duration(seconds: 1));
      await notificationsDone.timeout(const Duration(seconds: 1));
      expect(connection.connectionState, ConnectionState.closed);
      expect(connection.hasConnected, isFalse);
      await expectLater(
        connection.connect(),
        throwsA(isA<PostgresqlException>()),
      );
    });

    test('terminal close finishes streams after a recoverable socket loss',
        () async {
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = server.first;
      final connection = CoreConnection(
        'test_user',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        database: 'test_database',
        allowAttemptToReconnect: true,
      );
      addTearDown(() async {
        await connection.close();
        await server.close();
      });
      final noticesDone = connection.notices.drain<void>();
      final notificationsDone = connection.notifications.drain<void>();

      final opening = connection.connect();
      final backend = await accepted;
      await _SocketReader(backend).readStartup();
      await _respondAuthenticationOk(backend);
      await opening;

      backend.destroy();
      await _waitForState(connection, ConnectionState.closed);
      await connection.close();

      await noticesDone.timeout(const Duration(seconds: 1));
      await notificationsDone.timeout(const Duration(seconds: 1));
    });

    test('reconnect cycle is shared and honors the exact attempt limit',
        () async {
      final server =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final firstAccepted = Completer<Socket>();
      var acceptedCount = 0;
      final serverSubscription = server.listen((socket) {
        acceptedCount++;
        if (acceptedCount == 1) {
          firstAccepted.complete(socket);
        } else {
          socket.destroy();
        }
      });
      final connection = CoreConnection(
        'test_user',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        database: 'test_database',
        allowAttemptToReconnect: true,
        reconnectPolicy: const ReconnectPolicy(
          maxAttempts: 3,
          initialDelay: Duration.zero,
          maxDelay: Duration.zero,
          jitterFactor: 0,
        ),
      );
      addTearDown(() async {
        await connection.close();
        await serverSubscription.cancel();
        await server.close();
      });

      final opening = connection.connect();
      final backend = await firstAccepted.future;
      await _SocketReader(backend).readStartup();
      await _respondAuthenticationOk(backend);
      await opening;
      backend.destroy();
      await _waitForState(connection, ConnectionState.closed);

      await expectLater(
        Future.wait<void>(<Future<void>>[
          connection.tryReconnect(),
          connection.tryReconnect(),
        ]),
        throwsA(isA<PostgresqlException>()),
      );
      expect(acceptedCount, 4,
          reason: 'One initial socket plus exactly three reconnect attempts.');
    });
  }, timeout: const Timeout(Duration(seconds: 20)));
}

Future<void> _respondAuthenticationOk(Socket socket) async {
  final auth = PgWriteBuffer();
  _message(auth, 0x52, () => auth.writeInt32(0));
  _message(auth, 0x5a, () => auth.writeUint8(0x49));
  socket.add(auth.toBytes());
  await socket.flush();
}

Future<void> _waitForState(
    CoreConnection connection, ConnectionState expected) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (identical(connection.connectionState, expected)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError(
      'Connection did not reach $expected; was ${connection.connectionState}.');
}

class _Person {
  final int id;
  final String name;
  final bool active;

  const _Person(this.id, this.name, this.active);

  @override
  bool operator ==(Object other) =>
      other is _Person &&
      other.id == id &&
      other.name == name &&
      other.active == active;

  @override
  int get hashCode => Object.hash(id, name, active);
}

class _WireMessage {
  final int code;
  final Uint8List body;

  _WireMessage(this.code, this.body);
}

class _SocketReader {
  final StreamIterator<Uint8List> _iterator;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;

  _SocketReader(Socket socket) : _iterator = StreamIterator<Uint8List>(socket);

  Future<Uint8List> readStartup() async {
    final header = await read(4);
    final length = ByteData.sublistView(header).getUint32(0, Endian.big);
    if (length < 8) throw StateError('Invalid startup length $length.');
    return read(length - 4);
  }

  Future<List<_WireMessage>> readMessages(int count) async {
    final result = <_WireMessage>[];
    for (var i = 0; i < count; i++) {
      final header = await read(5);
      final length = ByteData.sublistView(header).getUint32(1, Endian.big);
      result.add(_WireMessage(header[0], await read(length - 4)));
    }
    return result;
  }

  Future<Uint8List> read(int count) async {
    final result = Uint8List(count);
    var written = 0;
    while (written < count) {
      if (_offset == _chunk.length) {
        if (!await _iterator.moveNext()) {
          throw StateError('Socket closed with ${count - written} bytes left.');
        }
        _chunk = _iterator.current;
        _offset = 0;
      }
      final available = _chunk.length - _offset;
      final take = available < count - written ? available : count - written;
      result.setRange(written, written + take, _chunk, _offset);
      written += take;
      _offset += take;
    }
    return result;
  }
}

void _message(PgWriteBuffer writer, int code, void Function() body) {
  writer.startMessage(code);
  body();
  writer.endMessage();
}

Future<void> _respondSelect(Socket socket,
    {required bool includeDescription,
    required bool binary,
    bool? descriptionBinary,
    bool fragmented = false,
    int rowCount = 1,
    int transactionStatus = 0x49,
    int closeCompleteCount = 0}) async {
  final writer = PgWriteBuffer();
  for (var i = 0; i < closeCompleteCount; i++) {
    _message(writer, 0x33, () {}); // CloseComplete
  }
  if (includeDescription) {
    _message(writer, 0x31, () {}); // ParseComplete
    _message(writer, 0x74, () => writer.writeUint16(0));
    _message(writer, 0x54, () {
      final describedAsBinary = descriptionBinary ?? binary;
      writer.writeUint16(3);
      _writeColumn(writer, 'id', 23, 4, describedAsBinary ? 1 : 0);
      _writeColumn(writer, 'name', 25, -1, describedAsBinary ? 1 : 0);
      _writeColumn(writer, 'active', 16, 1, describedAsBinary ? 1 : 0);
    });
  }
  _message(writer, 0x32, () {}); // BindComplete
  for (var i = 0; i < rowCount; i++) {
    _message(writer, 0x44, () {
      writer.writeUint16(3);
      if (binary) {
        writer.writeInt32(4);
        writer.writeInt32(42);
        _writeField(writer, ascii.encode('hello'));
        writer.writeInt32(1);
        writer.writeUint8(1);
      } else {
        _writeField(writer, ascii.encode('42'));
        _writeField(writer, ascii.encode('hello'));
        _writeField(writer, ascii.encode('t'));
      }
    });
  }
  _message(writer, 0x43, () => _writeCString(writer, 'SELECT $rowCount'));
  _message(writer, 0x5a, () => writer.writeUint8(transactionStatus));
  final bytes = writer.toBytes();
  if (!fragmented) {
    socket.add(bytes);
    await socket.flush();
    return;
  }

  // Exercise header and DataRow fragmentation through the actual Socket path.
  const pieces = <int>[1, 2, 4, 3, 7, 1, 11, 5];
  var offset = 0;
  var piece = 0;
  while (offset < bytes.length) {
    final requested = pieces[piece++ % pieces.length];
    final end =
        offset + requested < bytes.length ? offset + requested : bytes.length;
    socket.add(Uint8List.sublistView(bytes, offset, end));
    await socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    offset = end;
  }
}

Future<void> _respondOneColumnSelect(Socket socket,
    {required bool includeDescription,
    required int oid,
    required List<int> value}) async {
  final writer = PgWriteBuffer();
  if (includeDescription) {
    _message(writer, 0x31, () {}); // ParseComplete
    _message(writer, 0x74, () => writer.writeUint16(0));
    _message(writer, 0x54, () {
      writer.writeUint16(1);
      // Describe Statement reports text; Bind controls the portal's DataRows.
      _writeColumn(writer, 'extension_value', oid, -1, 0);
    });
  }
  _message(writer, 0x32, () {}); // BindComplete
  _message(writer, 0x44, () {
    writer.writeUint16(1);
    _writeField(writer, value);
  });
  _message(writer, 0x43, () => _writeCString(writer, 'SELECT 1'));
  _message(writer, 0x5a, () => writer.writeUint8(0x49));
  socket.add(writer.toBytes());
  await socket.flush();
}

Future<void> _respondErrorAndReady(Socket socket,
    {required String code, required String message}) async {
  final writer = PgWriteBuffer();
  _message(writer, 0x45, () {
    writer.writeUint8(0x53); // Severity.
    _writeCString(writer, 'ERROR');
    writer.writeUint8(0x43); // SQLSTATE code.
    _writeCString(writer, code);
    writer.writeUint8(0x4d); // Message.
    _writeCString(writer, message);
    writer.writeUint8(0);
  });
  _message(writer, 0x5a, () => writer.writeUint8(0x49));
  socket.add(writer.toBytes());
  await socket.flush();
}

Future<void> _respondCommand(
    Socket socket, String command, int transactionStatus) async {
  final writer = PgWriteBuffer();
  _message(writer, 0x43, () => _writeCString(writer, command));
  _message(writer, 0x5a, () => writer.writeUint8(transactionStatus));
  socket.add(writer.toBytes());
  await socket.flush();
}

void _writeColumn(
    PgWriteBuffer writer, String name, int oid, int size, int format) {
  _writeCString(writer, name);
  writer.writeUint32(0);
  writer.writeUint16(0);
  writer.writeUint32(oid);
  writer.writeUint16(size & 0xffff);
  writer.writeInt32(-1);
  writer.writeUint16(format);
}

void _writeField(PgWriteBuffer writer, List<int> value) {
  writer.writeInt32(value.length);
  writer.writeBytes(value);
}

void _writeCString(PgWriteBuffer writer, String value) {
  writer.writeBytes(utf8.encode(value));
  writer.writeUint8(0);
}

List<int> _bindResultFormats(Uint8List body) {
  var offset = _readCString(body, 0).nextOffset;
  offset = _readCString(body, offset).nextOffset;
  final data = ByteData.sublistView(body);
  final parameterFormatCount = data.getUint16(offset, Endian.big);
  offset += 2 + parameterFormatCount * 2;
  final parameterCount = data.getUint16(offset, Endian.big);
  offset += 2;
  for (var i = 0; i < parameterCount; i++) {
    final length = data.getInt32(offset, Endian.big);
    offset += 4;
    if (length >= 0) offset += length;
  }
  final resultCount = data.getUint16(offset, Endian.big);
  offset += 2;
  return List<int>.generate(
      resultCount, (index) => data.getUint16(offset + index * 2, Endian.big));
}

String _parseSql(Uint8List body) {
  final statement = _readCString(body, 0);
  return _readCString(body, statement.nextOffset).value;
}

_CString _readCString(Uint8List bytes, int offset) {
  final end = bytes.indexOf(0, offset);
  if (end < 0) throw const FormatException('Missing C-string terminator.');
  return _CString(ascii.decoder.convert(bytes, offset, end), end + 1);
}

bool _containsCString(Uint8List bytes, String value) {
  final needle = <int>[...ascii.encode(value), 0];
  for (var start = 0; start + needle.length <= bytes.length; start++) {
    var matches = true;
    for (var i = 0; i < needle.length; i++) {
      if (bytes[start + i] != needle[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

class _CString {
  final String value;
  final int nextOffset;

  _CString(this.value, this.nextOffset);
}
