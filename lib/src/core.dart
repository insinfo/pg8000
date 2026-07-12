import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dargres/src/timezone_settings.dart';
import 'connection_interface.dart';
import 'results.dart';
import 'row_info.dart';

import 'dependencies/sasl_scram/sasl_scram.dart';
import 'to_statement.dart';
import 'utils/utils.dart';

import 'authentication_request_type.dart';
import 'client_notice.dart';
import 'column_description.dart';
import 'connection_settings.dart';
import 'constants.dart';
import 'converters.dart';
import 'exceptions.dart';
import 'fast/pg_read_buffer.dart';
import 'fast/pg_write_buffer.dart';
import 'fast/result_schema.dart';
import 'fast/row_view.dart';
import 'query.dart';
import 'server_info.dart';
import 'server_notice.dart';
import 'ssl_context.dart';

import 'transaction_context.dart';
import 'connection_state.dart';

import 'transaction_state.dart';

class CoreConnection implements ConnectionInterface {
  late List<int> userBytes;
  String? host;
  String? database;
  int port;
  late List<int> passwordBytes;
  String sourceAddress;
  bool isUnixSocket = false;
  SslContext? sslContext;

  bool tcpKeepalive;

  /// PostgreSQL versions older than 8.2 do not support `application_name`.
  String? applicationName;
  dynamic replication;
  ScramAuthenticator? scramAuthenticator;
  late AuthenticationRequestType authenticationRequestType;

  String? connectionName;
  int connectionId = 0;

  Completer<CoreConnection> _connected = Completer<CoreConnection>();
  Future<CoreConnection>? _connectOperation;
  Future<void>? _reconnectOperation;
  Future<void>? _closeOperation;
  bool _terminallyClosed = false;
  int _lifecycleGeneration = 0;

  late Socket _socket;
  Socket? _openingSocket;
  bool _hasSocket = false;
  StreamSubscription<Uint8List>? _socketSubscription;
  int _socketGeneration = 0;
  Timer? _commandTimer;
  Timer? _cancelGraceTimer;
  Future<bool>? _cancelRequestOperation;

  String defaultCodeCharset = 'ascii';
  String textCharset = 'utf8';

  late TypeConverter typeConverter;

  StreamController<dynamic> _notifications =
      StreamController<dynamic>.broadcast();
  Stream<dynamic> get notifications => _notifications.stream;

  StreamController<dynamic> _notices = StreamController<dynamic>.broadcast();
  Stream<dynamic> get notices => _notices.stream;

  ServerInfo serverInfo = ServerInfo(timeZone: TimeZoneSettings('UTC'));

  String user;
  String? password;

  Duration connectionTimeout = Duration(seconds: 180);
  Duration? commandTimeout;
  Duration cancelGracePeriod;

  ServerNotice? lastServerNotice;

  ///  Int32(196608) - Protocol version number.  Version 3.0.
  int protocol = 196608;

  Map<String, dynamic> _initParams = <String, dynamic>{};

  ConnectionState _connectionState = ConnectionState.notConnected;

  ConnectionState get connectionState => _connectionState;
  Future<CoreConnection> get whenConnected => _connected.future;

  /// Allows reconnect attempts after a PostgreSQL server restart.
  bool allowAttemptToReconnect = false;
  final ReconnectPolicy reconnectPolicy;
  final math.Random _reconnectRandom;

  int get tryReconnectLimit => reconnectPolicy.maxAttempts;

  TransactionState transactionState = TransactionState.unknown;

  int backendPid = 0;
  int _backendSecretKey = 0;
  bool _hasBackendKeyData = false;

  bool hasConnected = false;
  final Queue<Query> _sendQueryQueue = Queue<Query>();
  Query? _query;

  int prepareStatementId = 0;

  /// Maximum number of server-side statements retained by the fast query
  /// APIs. The cache belongs to this physical connection.
  final int statementCacheCapacity;
  final LinkedHashMap<String, Query> _statementCache =
      LinkedHashMap<String, Query>();
  final Map<String, Completer<void>> _statementPreparations =
      <String, Completer<void>>{};
  final Map<String, Uint8List> _pendingStatementCloses = <String, Uint8List>{};
  final Map<String, Uint8List> _deferredStatementCloses = <String, Uint8List>{};
  final Map<String, int> _statementUseCounts = <String, int>{};
  int _statementCacheGeneration = 0;
  int statementCacheHits = 0;
  int statementCacheMisses = 0;
  int statementCacheEvictions = 0;
  int statementCacheInvalidations = 0;

  int get statementCacheLength => _statementCache.length;

  final Queue<TransactionContext> _transactionQueue =
      Queue<TransactionContext>();
  TransactionContext? _currentTransaction;
  int _transactionId = 0;

  TimeZoneSettings timeZone = TimeZoneSettings('UTC');

  /// [textCharset] utf8 | latin1 | ascii
  ///
  /// [host] ip, dns or unix socket
  ///
  /// [timeZone] = default = TimeZoneSettings('UTC')
  CoreConnection(
    this.user, {
    this.host = 'localhost',
    this.database,
    this.port = 5432,
    this.password,
    this.sourceAddress = '',
    this.isUnixSocket = false,
    this.sslContext,
    this.connectionTimeout = const Duration(seconds: 180),
    this.commandTimeout,
    this.cancelGracePeriod = const Duration(seconds: 5),
    this.tcpKeepalive = false,
    this.applicationName,
    this.replication,
    this.connectionName,
    this.textCharset = 'utf8',
    this.allowAttemptToReconnect = false,
    this.reconnectPolicy = const ReconnectPolicy(),
    math.Random? reconnectRandom,
    this.statementCacheCapacity = 64,
    TimeZoneSettings? timeZone,
  }) : _reconnectRandom = reconnectRandom ?? math.Random() {
    reconnectPolicy.validate();
    if (commandTimeout != null && commandTimeout! <= Duration.zero) {
      throw ArgumentError.value(
          commandTimeout, 'commandTimeout', 'must be greater than zero');
    }
    if (cancelGracePeriod <= Duration.zero) {
      throw ArgumentError.value(cancelGracePeriod, 'cancelGracePeriod',
          'must be greater than zero');
    }
    if (statementCacheCapacity < 0) {
      throw ArgumentError.value(
          statementCacheCapacity, 'statementCacheCapacity', 'must be >= 0');
    }
    this.timeZone = timeZone ?? TimeZoneSettings('UTC');
    serverInfo.timeZone = this.timeZone;
    typeConverter =
        TypeConverter(textCharset, serverInfo, connectionName: connectionName);
    _init();
  }

  factory CoreConnection.fromSettings(ConnectionSettings settings) {
    return CoreConnection(
      settings.user,
      host: settings.host,
      database: settings.database,
      port: settings.port,
      password: settings.password,
      sourceAddress: settings.sourceAddress,
      isUnixSocket: settings.isUnixSocket,
      sslContext: settings.sslContext,
      connectionTimeout: settings.connectionTimeout,
      commandTimeout: settings.commandTimeout,
      cancelGracePeriod: settings.cancelGracePeriod,
      tcpKeepalive: settings.tcpKeepalive,
      applicationName: settings.applicationName,
      replication: settings.replication,
      connectionName: settings.connectionName,
      textCharset: settings.textCharset,
      allowAttemptToReconnect: settings.allowAttemptToReconnect,
      reconnectPolicy: settings.reconnectPolicy,
      statementCacheCapacity: settings.statementCacheCapacity,
      timeZone: settings.timeZone,
    );
  }

  /// Create Connection from uri
  /// Example:  var uri = 'postgres://postgres:dart@localhost:5432/sistemas';
  /// final connection = CoreConnection.fromUri(uri);
  factory CoreConnection.fromUri(String uriString) {
    var settings = ConnectionSettings.fromUri(uriString);
    return CoreConnection.fromSettings(settings);
  }

  void _init() {
    connectionName ??= 'dargres_$connectionId';
    connectionId++;

    _initParams = <String, dynamic>{
      "user": user,
      "database": database,
      "replication": replication,
      "timezone": timeZone.value
    };
    if (applicationName != null) {
      _initParams['application_name'] = applicationName;
    }

    var initParamsEntries = [..._initParams.entries];
    for (var entry in initParamsEntries) {
      if (entry.value is String) {
        _initParams[entry.key] =
            typeConverter.charsetEncode(entry.value, textCharset);
      } else if (entry.value == null) {
        _initParams.remove(entry.key);
      }
    }
    userBytes = _initParams['user'];

    if (password is String) {
      passwordBytes = typeConverter.charsetEncode(password!, textCharset);
    }
  }

  void _setKeepAlive(Socket socket) {
    RawSocketOption option;
    if (Platform.isAndroid || Platform.isLinux) {
      option = RawSocketOption.fromBool(0x1, 0x0009, true);
    } else {
      option = RawSocketOption.fromBool(0xffff, 0x0008, true);
    }
    socket.setRawOption(option);
  }

  @override
  Future<CoreConnection> connect({int? delayBeforeConnect}) {
    if (_terminallyClosed) {
      return Future<CoreConnection>.error(PostgresqlException(
          'Connection has been closed and cannot be reopened.',
          connectionName: connectionName));
    }
    final opening = _connectOperation;
    if (opening != null) return opening;
    if (hasConnected && _connectionState != ConnectionState.closed) {
      return Future<CoreConnection>.value(this);
    }

    final generation = ++_lifecycleGeneration;
    final operation = _openConnection(generation, delayBeforeConnect);
    _connectOperation = operation;
    operation.then<void>(
      (_) {
        if (identical(_connectOperation, operation)) _connectOperation = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_connectOperation, operation)) _connectOperation = null;
      },
    );
    return operation;
  }

  Future<CoreConnection> _openConnection(
      int lifecycleGeneration, int? delayBeforeConnect) async {
    if (_notices.isClosed) {
      _notices = StreamController<dynamic>.broadcast();
    }
    if (_notifications.isClosed) {
      _notifications = StreamController<dynamic>.broadcast();
    }
    _buffer.clear();
    _msgType = null;
    _msgLength = null;
    _maintenanceCloseResponses = 0;
    _retryQueryAfterMaintenanceError = false;
    // Preserve a `whenConnected` future obtained before the first connect().
    if (_connected.isCompleted) _connected = Completer<CoreConnection>();
    _connectionState = ConnectionState.socketConnecting;

    if (delayBeforeConnect != null) {
      await Future.delayed(Duration(seconds: delayBeforeConnect));
      if (!_isCurrentLifecycle(lifecycleGeneration)) return _connected.future;
    }

    Socket? openedSocket;
    try {
      if (!isUnixSocket && host != null) {
        openedSocket = await Socket.connect(
          host,
          port,
          sourceAddress: sourceAddress.isEmpty ? null : sourceAddress,
        ).timeout(connectionTimeout);
      } else if (isUnixSocket && host != null) {
        openedSocket = await Socket.connect(
                InternetAddress(host!, type: InternetAddressType.unix), port)
            .timeout(connectionTimeout);
      } else {
        throw PostgresqlException('one of host or unix_sock must be provided',
            connectionName: connectionName);
      }
      if (!_isCurrentLifecycle(lifecycleGeneration)) {
        openedSocket.destroy();
        return _connected.future;
      }
      _openingSocket = openedSocket;

      if (sslContext != null) {
        openedSocket = await _connectSsl(openedSocket);
        _openingSocket = openedSocket;
      }
      if (!_isCurrentLifecycle(lifecycleGeneration)) {
        openedSocket.destroy();
        return _connected.future;
      }
      _socket = openedSocket;
      _openingSocket = null;
      _hasSocket = true;
      if (tcpKeepalive) _setKeepAlive(_socket);
    } catch (error, stackTrace) {
      openedSocket?.destroy();
      if (identical(_openingSocket, openedSocket)) _openingSocket = null;
      _hasSocket = false;
      final exception = error is PostgresqlException
          ? error
          : PostgresqlException(
              "Can't create a connection to host $host and port $port "
              '(timeout is: $connectionTimeout and sourceAddress is: '
              '$sourceAddress): $error',
              errorCode: error,
              connectionName: connectionName);
      if (_isCurrentLifecycle(lifecycleGeneration)) {
        _connectionState = ConnectionState.closed;
      }
      if (!_connected.isCompleted) {
        _connected.completeError(exception, stackTrace);
      }
      return _connected.future;
    }

    _connectionState = ConnectionState.socketConnected;

    final socket = _socket;
    final generation = ++_socketGeneration;
    _socketSubscription = socket.listen(
      (data) {
        if (generation == _socketGeneration && identical(socket, _socket)) {
          _readData(data);
        }
      },
      onError: (Object error) {
        if (generation == _socketGeneration && identical(socket, _socket)) {
          _handleSocketError(error);
        }
      },
      onDone: () {
        if (generation == _socketGeneration && identical(socket, _socket)) {
          _handleSocketClosed();
        }
      },
    );
    try {
      _sendStartupMessage();
    } catch (error, stackTrace) {
      _destroy(reason: error, stackTrace: stackTrace);
      return _connected.future;
    }

    try {
      return await _connected.future.timeout(connectionTimeout);
    } on TimeoutException catch (error, stackTrace) {
      final exception = PostgresqlException(
          'Timed out while waiting for PostgreSQL startup authentication.',
          errorCode: error,
          connectionName: connectionName);
      if (_isCurrentLifecycle(lifecycleGeneration)) {
        _destroy(reason: exception, stackTrace: stackTrace);
      }
      Error.throwWithStackTrace(exception, stackTrace);
    }
  }

  bool _isCurrentLifecycle(int generation) =>
      !_terminallyClosed && generation == _lifecycleGeneration;

  Future<SecureSocket> _connectSsl(Socket socket) async {
    final response = Completer<int>();
    late final StreamSubscription<Uint8List> subscription;
    subscription = socket.listen((data) {
      if (data.isNotEmpty && !response.isCompleted) response.complete(data[0]);
    }, onError: (Object error, StackTrace stackTrace) {
      if (!response.isCompleted) response.completeError(error, stackTrace);
    }, onDone: () {
      if (!response.isCompleted) {
        response.completeError(StateError('Socket closed during SSL request.'));
      }
    });

    late final int answer;
    try {
      socket.add(const <int>[0, 0, 0, 8, 4, 210, 22, 47]);
      await socket.flush();
      answer = await response.future.timeout(connectionTimeout);
    } finally {
      await subscription.cancel();
    }
    if (answer != statementTarget) {
      throw PostgresqlException(
        'This PostgreSQL server rejected SSL connections.',
        connectionName: connectionName,
      );
    }
    return SecureSocket.secure(
      socket,
      context: sslContext!.context,
      onBadCertificate: sslContext!.onBadCertificate,
      supportedProtocols: sslContext!.supportedProtocols,
    ).timeout(connectionTimeout);
  }

  /// Executes a minimal round trip and throws when this connection cannot
  /// reach PostgreSQL. No background timer or periodic traffic is created.
  @override
  Future<void> ping() async {
    if (_terminallyClosed || !hasConnected) {
      throw PostgresqlException('Connection is not open.',
          connectionName: connectionName);
    }
    var received = false;
    await queryEach(
      'SELECT 1::int4',
      (row) => received = row.getInt(0) == 1,
      requireBinaryResults: true,
    );
    if (!received) {
      throw PostgresqlException('PostgreSQL health check returned no row.',
          connectionName: connectionName);
    }
  }

  /// Returns whether [ping] completes successfully.
  @override
  Future<bool> checkHealth() async {
    try {
      await ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends PostgreSQL's out-of-band CancelRequest for the active command.
  ///
  /// The request uses a separate short-lived socket, as required by the wire
  /// protocol. New work is held behind a barrier until that socket is closed,
  /// preventing a late cancel packet from reaching the next command.
  @override
  Future<bool> cancelCurrentQuery() async {
    final query = _query;
    if (query == null) return false;
    final sent = await _requestQueryCancellation(query);
    if (sent && identical(_query, query)) {
      _startCancelGrace(
        query,
        PostgresqlException(
          'PostgreSQL did not acknowledge CancelRequest within '
          '$cancelGracePeriod.',
          connectionName: connectionName,
          sql: query.getSql,
        ),
      );
    }
    return sent;
  }

  Future<bool> _requestQueryCancellation(Query query) {
    final current = _cancelRequestOperation;
    if (current != null) return current;

    final operation = _sendCancelRequest(query);
    _cancelRequestOperation = operation;
    operation.then<void>(
      (_) => _finishCancelRequest(operation),
      onError: (Object _, StackTrace __) => _finishCancelRequest(operation),
    );
    return operation;
  }

  void _finishCancelRequest(Future<bool> operation) {
    if (!identical(_cancelRequestOperation, operation)) return;
    _cancelRequestOperation = null;
    Timer.run(_processSendQueryQueue);
  }

  Future<bool> _sendCancelRequest(Query query) async {
    if (!identical(_query, query)) return false;
    if (!_hasBackendKeyData) {
      throw PostgresqlException(
        'PostgreSQL did not provide BackendKeyData; the active command '
        'cannot be cancelled safely.',
        connectionName: connectionName,
      );
    }

    final currentHost = host;
    if (currentHost == null) {
      throw PostgresqlException(
        'The connection host is unavailable for CancelRequest.',
        connectionName: connectionName,
      );
    }
    final processId = backendPid;
    final secretKey = _backendSecretKey;
    Socket? cancelSocket;
    try {
      if (isUnixSocket) {
        cancelSocket = await Socket.connect(
          InternetAddress(currentHost, type: InternetAddressType.unix),
          port,
        ).timeout(connectionTimeout);
      } else {
        cancelSocket = await Socket.connect(
          currentHost,
          port,
          sourceAddress: sourceAddress.isEmpty ? null : sourceAddress,
        ).timeout(connectionTimeout);
      }

      // The command may have completed while the cancel socket was opening.
      // In that case, never send a packet that could cancel the next command.
      if (!identical(_query, query) || _terminallyClosed) return false;
      cancelSocket.add(cancelRequestBytes(processId, secretKey));
      await cancelSocket.flush().timeout(connectionTimeout);
      return true;
    } finally {
      cancelSocket?.destroy();
    }
  }

  void _armCommandTimer(Query query) {
    _commandTimer?.cancel();
    final timeout = commandTimeout;
    if (timeout == null) return;
    _commandTimer = Timer(timeout, () {
      _commandTimer = null;
      if (!identical(_query, query)) return;
      final error = TimeoutException(
        'PostgreSQL command timed out after $timeout.',
        timeout,
      );
      query.clientError ??= error;
      query.clientStackTrace ??= StackTrace.current;
      _cancelTimedOutQuery(query, error);
    });
  }

  void _cancelTimedOutQuery(Query query, TimeoutException timeoutError) {
    _requestQueryCancellation(query).then<void>((sent) {
      if (!identical(_query, query)) return;
      if (!sent) {
        _destroy(reason: timeoutError);
        return;
      }
      _startCancelGrace(query, timeoutError);
    }, onError: (Object _, StackTrace stackTrace) {
      if (identical(_query, query)) {
        _destroy(reason: timeoutError, stackTrace: stackTrace);
      }
    });
  }

  void _startCancelGrace(Query query, Object error) {
    _cancelGraceTimer?.cancel();
    _cancelGraceTimer = Timer(cancelGracePeriod, () {
      _cancelGraceTimer = null;
      if (identical(_query, query)) {
        _destroy(reason: error);
      }
    });
  }

  void _clearCommandTimers() {
    _commandTimer?.cancel();
    _commandTimer = null;
    _cancelGraceTimer?.cancel();
    _cancelGraceTimer = null;
  }

  /// Executes SQL through the simple-query protocol and returns affected rows.
  /// Example: con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;')
  @override
  Future<int> execute(String sql) async {
    try {
      var query = Query(sql);
      query.queryType = QueryType.simple;
      await _enqueueQuery(query);
      await query.stream.toList();
      return query.rowsAffected.value;
    } catch (ex, st) {
      return Future.error(ex, st);
    }
  }

  /// Executes a query through PostgreSQL's simple-query protocol.
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  @override
  Future<Results> querySimple(String sql) async {
    var r = await querySimpleAsStream(sql);
    return r.toResults();
  }

  /// Streams a query through PostgreSQL's simple-query protocol.
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  @override
  Future<ResultStream> querySimpleAsStream(String sql) async {
    var query = Query(sql);
    query.queryType = QueryType.simple;
    await _enqueueQuery(query);
    var resultStream = query.stream;
    resultStream.rowsAffected = query.rowsAffected;
    return resultStream;
  }

  /// Executes an uncached unnamed extended-protocol statement.
  ///
  /// [params] must be a `List` for PostgreSQL or question-mark placeholders
  /// and a `Map` for named placeholders.
  /// Example: com.queryUnnamed(r'select * from crud_teste.pessoas limit $1', [1]);
  @override
  Future<Results> queryUnnamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false}) async {
    return executeDirectResults(sql, params,
        placeholderIdentifier: placeholderIdentifier, useCache: false);
  }

  @override
  Future<Results> queryNamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false}) async {
    return executeDirectResults(sql, params,
        placeholderIdentifier: placeholderIdentifier,
        useCache: !isDeallocate);
  }

  /// Prepares a server-side statement.
  ///
  /// [params] must be a `List` for PostgreSQL or question-mark placeholders
  /// and a `Map` for named placeholders.
  /// Example:
  /// final statement = await prepareStatement('SELECT * FROM table LIMIT $1', [0]);
  /// final result = await executeStatement(statement);
  @override
  Future<Query> prepareStatement(
    String sql,
    dynamic params, {
    bool isUnamedStatement = false,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
  }) async {
    var query = Query(sql,
        params: params, placeholderIdentifier: placeholderIdentifier);

    query.connection = this;
    query.error = null;
    query.isUnamedStatement = isUnamedStatement;
    query.prepareStatementId = prepareStatementId;
    prepareStatementId++;
    query.queryType = QueryType.prepareStatement;
    await _enqueueQuery(query);
    await query.stream.isEmpty;
    return query;
  }

  /// Executes a statement created by [prepareStatement].
  @override
  Future<Results> executeStatement(Query query,
      {bool isDeallocate = false}) async {
    var stm = await executeStatementAsStream(query);
    var result = stm.toResults();

    if (isDeallocate == true) {
      await execute('DEALLOCATE ${query.statementName}');
    }
    return result;
  }

  /// Streams a statement created by [prepareStatement].
  @override
  Future<ResultStream> executeStatementAsStream(Query query) async {
    try {
      final newQuery = query.execution(query.preparedParams);
      await _enqueueQuery(newQuery);
      return newQuery.stream;
    } catch (ex, st) {
      return ResultStream.fromFuture(Future.error(ex, st));
    }
  }

  @override
  Future<TransactionContext> beginTransaction() async {
    var transaction = TransactionContext(_transactionId, this);
    final commandBegin = 'BEGIN';
    await _enqueueTransaction(transaction);
    await transaction.execute(commandBegin);
    _transactionId++;
    return transaction;
  }

  @override
  Future<void> rollBack(TransactionContext transaction) async {
    if (!identical(transaction, _currentTransaction)) {
      throw StateError('Cannot roll back a transaction that is not active.');
    }
    await transaction.execute('ROLLBACK');
    transaction.markCompleted();
    _currentTransaction = null;
    Timer.run(_processTransactionQueue);
  }

  @override
  Future<void> commit(TransactionContext transaction) async {
    if (!identical(transaction, _currentTransaction)) {
      throw StateError('Cannot commit a transaction that is not active.');
    }
    await transaction.execute('COMMIT');
    transaction.markCompleted();
    _currentTransaction = null;
    Timer.run(_processTransactionQueue);
  }

  @override
  Future<T> runInTransaction<T>(
      Future<T> Function(TransactionContext ctx) operation) async {
    final transa = await beginTransaction();
    try {
      final result = await operation(transa);
      await commit(transa);
      return result;
    } catch (_) {
      if (identical(transa, _currentTransaction) &&
          _connectionState != ConnectionState.closed) {
        try {
          await rollBack(transa);
        } catch (_) {
          // Preserve the original operation/commit error.
        }
      }
      rethrow;
    }
  }

  Future<void> _enqueueTransaction(TransactionContext transaction) async {
    if (_connectionState == ConnectionState.closed) {
      if (allowAttemptToReconnect) {
        await tryReconnect();
      } else {
        throw PostgresqlException(
            'Connection is closed, cannot execute transaction.',
            errorCode: 500,
            serverMessage: lastServerNotice,
            serverErrorCode: lastServerNotice?.code,
            connectionName: connectionName);
      }
    }
    _transactionQueue.addLast(transaction);
    Timer.run(_processTransactionQueue);
  }

  void _processTransactionQueue() async {
    if (_transactionQueue.isEmpty) {
      return;
    }
    if (_currentTransaction != null) {
      return;
    }
    if (_connectionState != ConnectionState.idle) {
      return;
    }
    _currentTransaction = _transactionQueue.removeFirst();
    Timer.run(_processSendQueryQueue);
  }

  Future<void> _enqueueQuery(Query query) async {
    if (_connectionState == ConnectionState.closed) {
      if (allowAttemptToReconnect) {
        await tryReconnect();
      } else {
        throw PostgresqlException('Connection is closed, cannot execute query.',
            errorCode: 500,
            serverMessage: lastServerNotice,
            connectionName: connectionName,
            serverErrorCode: lastServerNotice?.code);
      }
    }
    _sendQueryQueue.addLast(query);
    Timer.run(_processSendQueryQueue);
  }

  /// Reopens a recoverably disconnected connection using [reconnectPolicy].
  /// Concurrent callers share one reconnect cycle.
  Future<void> tryReconnect() {
    if (_terminallyClosed) {
      return Future<void>.error(PostgresqlException(
          'Connection has been closed and cannot reconnect.',
          connectionName: connectionName));
    }
    if (hasConnected && _connectionState != ConnectionState.closed) {
      return Future<void>.value();
    }
    final reconnecting = _reconnectOperation;
    if (reconnecting != null) return reconnecting;
    final opening = _connectOperation;
    if (opening != null) return opening.then<void>((_) {});

    final operation = _runReconnectCycle();
    _reconnectOperation = operation;
    operation.then<void>(
      (_) {
        if (identical(_reconnectOperation, operation)) {
          _reconnectOperation = null;
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_reconnectOperation, operation)) {
          _reconnectOperation = null;
        }
      },
    );
    return operation;
  }

  Future<void> _runReconnectCycle() async {
    final attempts = reconnectPolicy.maxAttempts;
    if (attempts == 0) {
      throw PostgresqlException('Reconnect is disabled by its zero-attempt policy.',
          connectionName: connectionName);
    }

    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      if (_terminallyClosed) {
        throw PostgresqlException(
            'Connection was closed while waiting to reconnect.',
            connectionName: connectionName);
      }
      final delay = reconnectPolicy.delayForAttempt(attempt,
          jitterUnit: _reconnectRandom.nextDouble());
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      if (_terminallyClosed) {
        throw PostgresqlException(
            'Connection was closed while waiting to reconnect.',
            connectionName: connectionName);
      }

      try {
        await connect();
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }

    final exception = PostgresqlException(
        'Reconnect failed after $attempts attempt${attempts == 1 ? '' : 's'}.',
        errorCode: lastError,
        connectionName: connectionName);
    Error.throwWithStackTrace(
        exception, lastStackTrace ?? StackTrace.current);
  }

  void _processSendQueryQueue() async {
    var queryQueue = _sendQueryQueue;
    if (_currentTransaction != null) {
      queryQueue = _currentTransaction!.sendQueryQueue;
    }

    if (queryQueue.isEmpty) {
      return;
    }
    if (_query != null) {
      return;
    }
    if (_cancelRequestOperation != null) {
      return;
    }
    if (_connectionState != ConnectionState.idle) {
      return;
    }

    _query = queryQueue.removeFirst();
    final query = _query!;

    try {
      if (query.queryType == QueryType.simple) {
        _sendExecuteSimpleStatement(query);
      } else if (query.queryType == QueryType.prepareStatement) {
        _sendPreparedStatement(query);
      } else if (query.queryType == QueryType.execStatement) {
        _sendExecuteStatement(query);
      } else if (query.queryType == QueryType.extended) {
        _sendExtendedStatement(query);
      }
    } catch (error, stackTrace) {
      if (error is _SocketWriteException) {
        _destroy(reason: error, stackTrace: stackTrace);
      } else {
        _query = null;
        _connectionState = ConnectionState.idle;
        _failQuery(query, error, stackTrace);
        Timer.run(_processSendQueryQueue);
      }
      return;
    }
    _connectionState = ConnectionState.busy;
    transactionState = TransactionState.unknown;
    _armCommandTimer(query);
  }

  dynamic _sendExecuteSimpleStatement(Query query) {
    if (_resetsServerStatementCache(query.getSql)) {
      clearStatementCache(closeStatements: false);
    }
    final writer = PgWriteBuffer();
    writer.startMessage(queryMessage);
    writer.writeBytes(_sqlBytes(query));
    writer.writeUint8(nullByte);
    writer.endMessage();
    _sendBuffer(writer);
  }

  @override
  Future<List<Map<String, dynamic>>> queryMaps(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    final maps = <Map<String, dynamic>>[];
    await executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        maps.add(query.resultSchema!
            .decodeMap(bytes, baseOffset: offset, messageLength: length));
      };
    },
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
    return maps;
  }

  @override
  Future<List<T>> queryTyped<T>(
    String sql,
    T Function(RowView row) mapper, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    final entities = <T>[];
    List<Object?>? values;
    RowView? view;
    await executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        final schema = query.resultSchema!;
        values ??=
            List<Object?>.filled(schema.columnCount, null, growable: false);
        schema.decodeRowInto(bytes, values!,
            baseOffset: offset, messageLength: length);
        view ??= RowView(values!, schema.nameToIndex);
        entities.add(mapper(view!));
      };
    },
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
    return entities;
  }

  @override
  Future<void> queryEach(
    String sql,
    void Function(RowView row) onRow, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    List<Object?>? values;
    RowView? view;
    await executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        final schema = query.resultSchema!;
        values ??=
            List<Object?>.filled(schema.columnCount, null, growable: false);
        schema.decodeRowInto(bytes, values!,
            baseOffset: offset, messageLength: length);
        view ??= RowView(values!, schema.nameToIndex);
        onRow(view!);
      };
    },
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
  }

  @override
  Future<Results> queryCached(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    return executeDirectResults(sql, params,
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
  }

  Future<Results> executeDirectResults(String sql, dynamic params,
      {TransactionContext? transaction,
      PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool useCache = true,
      bool requireBinaryResults = false}) async {
    final rows = <Row>[];
    final query = await executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        final schema = query.resultSchema!;
        rows.add(Row(
            schema.decodeRow(bytes, baseOffset: offset, messageLength: length),
            schema.columns,
            schema.nameToIndex));
      };
    },
        transaction: transaction,
        placeholderIdentifier: placeholderIdentifier,
        useCache: useCache,
        requireBinaryResults: requireBinaryResults);
    return Results(rows, query.rowsAffected);
  }

  /// Runs a direct result sink. By default, a cache miss uses
  /// Parse+Describe+Bind+Execute in one round-trip with text results. A hit
  /// sends Bind+Execute+Sync and requests binary only for columns with
  /// complete codecs. [requireBinaryResults] requests binary for every cold
  /// result column and rejects schemas without complete binary codecs.
  Future<Query> executeDirect(
      String sql, dynamic params, void Function(Query query) configure,
      {TransactionContext? transaction,
      PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool useCache = true,
      bool requireBinaryResults = false}) async {
    if (transaction == null && _currentTransaction != null) {
      throw StateError(
          'A transaction is active; execute this query through its '
          'TransactionContext.');
    }
    final suppliedParams = params ?? const <Object?>[];
    if ((placeholderIdentifier == PlaceholderIdentifier.pgDefault ||
            placeholderIdentifier == PlaceholderIdentifier.onlyQuestionMark) &&
        suppliedParams is! List) {
      throw ArgumentError.value(
          params, 'params', 'Positional query parameters must be a List.');
    }
    final prototype = Query(sql,
        params: suppliedParams,
        connection: this,
        requireBinaryResults: requireBinaryResults,
        placeholderIdentifier: placeholderIdentifier);
    final values = prototype.preparedParams;
    final resetsCache = _resetsServerStatementCache(prototype.getSql);
    final cacheEnabled =
        useCache && !resetsCache && statementCacheCapacity > 0;

    final key = prototype.getSql;
    final cacheGeneration = _statementCacheGeneration;
    final serverGeneration = _socketGeneration;
    final preparationKey = transaction == null
        ? 'global\u0000$key'
        : 'transaction:${transaction.transactionId}\u0000$key';
    final cached = cacheEnabled ? _statementCache.remove(key) : null;
    if (cached == null && cacheEnabled) {
      final pending = _statementPreparations[preparationKey];
      if (pending != null) {
        await pending.future;
        return executeDirect(sql, params, configure,
            transaction: transaction,
            placeholderIdentifier: placeholderIdentifier,
            useCache: useCache,
            requireBinaryResults: requireBinaryResults);
      }
    }
    late final Query query;
    final cacheHit = cached != null;
    if (cached != null) {
      statementCacheHits++;
      // Remove + insert provides access-order LRU semantics.
      _statementCache[key] = cached;
      _retainStatement(cached);
      query = cached.execution(values,
          requireBinaryResults: requireBinaryResults);
    } else {
      statementCacheMisses++;
      query = prototype;
      query.error = null;
      query.isUnamedStatement = !cacheEnabled;
      query.prepareStatementId = prepareStatementId++;
      query.queryType = QueryType.extended;
    }

    final preparation = !cacheHit && cacheEnabled
        ? (_statementPreparations[preparationKey] = Completer<void>())
        : null;

    query.transactionContext = transaction;
    var stored = false;
    try {
      configure(query);
      if (query.requireBinaryResults) {
        final schema = query.resultSchema;
        if (schema != null && !schema.supportsAllBinary) {
          throw _unsupportedBinaryResultsError(schema);
        }
      }
      final completed = query.completed;
      if (transaction == null) {
        await _enqueueQuery(query);
      } else {
        transaction.sendQueryQueue.addLast(query);
        Timer.run(_processSendQueryQueue);
      }
      await completed;
      if (resetsCache) clearStatementCache(closeStatements: false);
      if (!cacheHit &&
          cacheEnabled &&
          query.parseComplete &&
          serverGeneration == _socketGeneration) {
        if (cacheGeneration == _statementCacheGeneration) {
          _storeStatement(key, query);
          stored = true;
        } else {
          _scheduleStatementClose(query);
        }
      }
    } catch (_) {
      // A mapper error happens after Parse succeeded, so make sure an uncached
      // statement is still useful to subsequent executions. A server error
      // does not publish a cache entry.
      if (!cacheHit &&
          query.parseComplete &&
          serverGeneration == _socketGeneration) {
        final invalidPlan = query.error?.serverErrorCode == '0A000';
        if (cacheEnabled &&
            !invalidPlan &&
            cacheGeneration == _statementCacheGeneration) {
          _storeStatement(key, query);
          stored = true;
        } else {
          _scheduleStatementClose(query);
        }
      }
      rethrow;
    } finally {
      if (cacheHit) _releaseStatement(query);
      if (preparation != null) {
        _statementPreparations.remove(preparationKey);
        if (!preparation.isCompleted) preparation.complete();
      }
    }
    assert(cacheHit ||
        !cacheEnabled ||
        stored ||
        !query.parseComplete ||
        cacheGeneration != _statementCacheGeneration ||
        serverGeneration != _socketGeneration);
    return query;
  }

  bool _resetsServerStatementCache(String sql) {
    final command = sql.trimLeft().toUpperCase();
    return command.startsWith('DEALLOCATE ALL') ||
        command.startsWith('DISCARD ALL');
  }

  void _storeStatement(String key, Query completedQuery) {
    final replaced = _statementCache.remove(key);
    if (replaced != null &&
        replaced.statementName != completedQuery.statementName) {
      _scheduleStatementClose(replaced);
    }
    final preferredSchema = completedQuery.resultSchema?.withPreferredBinary();
    final template = completedQuery.statementTemplate(schema: preferredSchema);
    _statementCache[key] = template;

    while (_statementCache.length > statementCacheCapacity) {
      final oldestKey = _statementCache.keys.first;
      final evicted = _statementCache.remove(oldestKey)!;
      statementCacheEvictions++;
      _scheduleStatementClose(evicted);
    }
  }

  void _retainStatement(Query statement) {
    final name = statement.statementName;
    if (name.isEmpty) return;
    _statementUseCounts[name] = (_statementUseCounts[name] ?? 0) + 1;
  }

  void _releaseStatement(Query statement) {
    final name = statement.statementName;
    final count = _statementUseCounts[name];
    if (count == null) return;
    if (count > 1) {
      _statementUseCounts[name] = count - 1;
      return;
    }
    _statementUseCounts.remove(name);
    final deferred = _deferredStatementCloses.remove(name);
    if (deferred != null) _pendingStatementCloses[name] = deferred;
  }

  void _scheduleStatementClose(Query statement) {
    final name = statement.statementName;
    if (name.isEmpty) return;
    final bytes = statement.encodedStatementName ??
        Uint8List.fromList(
            typeConverter.charsetEncode(name, defaultCodeCharset));
    if ((_statementUseCounts[name] ?? 0) > 0) {
      _deferredStatementCloses[name] = bytes;
    } else {
      _pendingStatementCloses[name] = bytes;
    }
  }

  /// Clears local statement metadata. Server-side Close messages are batched
  /// into the next query when [closeStatements] is true.
  void clearStatementCache({bool closeStatements = true}) {
    _statementCacheGeneration++;
    if (closeStatements) {
      for (final statement in _statementCache.values) {
        _scheduleStatementClose(statement);
      }
    }
    _statementCache.clear();
    if (!closeStatements) {
      _pendingStatementCloses.clear();
      _deferredStatementCloses.clear();
    }
  }

  dynamic _sendPreparedStatement(Query query) {
    final writer = PgWriteBuffer();
    final closeCount = _writePendingStatementCloses(writer);
    _writeParse(writer, query);
    _writeDescribeStatement(writer, query);
    _writeEmptyMessage(writer, syncMessage);
    _sendBuffer(writer, statementCloseCount: closeCount);
  }

  void _sendExecuteStatement(Query query) {
    final schema = query.resultSchema;
    if (schema != null) {
      final preferred = schema.usesPreferredResultFormats
          ? schema
          : schema.withPreferredBinary();
      query.resultSchema = preferred;
      query.columns = preferred.columns;
      query.columnCount = preferred.columnCount;
    }
    final writer = PgWriteBuffer();
    final closeCount = _writePendingStatementCloses(writer);
    _writeBind(writer, query);
    _writeExecute(writer);
    _writeEmptyMessage(writer, syncMessage);
    _sendBuffer(writer, statementCloseCount: closeCount);
  }

  /// Cold one-round-trip extended query. Result OIDs are not known when Bind
  /// is serialized, so the default first execution requests text. Strict
  /// binary execution requests one binary format for all columns and validates
  /// their OIDs when RowDescription arrives. The description seeds the cache;
  /// default cache hits can use selective binary.
  void _sendExtendedStatement(Query query) {
    final writer = PgWriteBuffer();
    final closeCount = _writePendingStatementCloses(writer);
    _writeParse(writer, query);
    _writeDescribeStatement(writer, query);
    _writeBind(writer, query,
        forceTextResults: !query.requireBinaryResults,
        forceBinaryResults: query.requireBinaryResults);
    _writeExecute(writer);
    _writeEmptyMessage(writer, syncMessage);
    _sendBuffer(writer, statementCloseCount: closeCount);
  }

  Uint8List _sqlBytes(Query query) {
    return query.encodedSql ??= Uint8List.fromList(
        typeConverter.charsetEncode(query.getSql, textCharset));
  }

  Uint8List _statementNameBytes(Query query) {
    return query.encodedStatementName ??= Uint8List.fromList(
        typeConverter.charsetEncode(query.statementName, defaultCodeCharset));
  }

  void _writeParse(PgWriteBuffer writer, Query query) {
    writer.startMessage(parseMessage);
    writer.writeBytes(_statementNameBytes(query));
    writer.writeUint8(nullByte);
    writer.writeBytes(_sqlBytes(query));
    writer.writeUint8(nullByte);
    final oids = query.oids;
    writer.writeUint16(oids.length);
    for (final oid in oids) {
      writer.writeInt32(oid == -1 ? 0 : oid as int);
    }
    writer.endMessage();
  }

  void _writeDescribeStatement(PgWriteBuffer writer, Query query) {
    writer.startMessage(describeMessage);
    writer.writeUint8(statementTarget);
    writer.writeBytes(_statementNameBytes(query));
    writer.writeUint8(nullByte);
    writer.endMessage();
  }

  void _writeBind(PgWriteBuffer writer, Query query,
      {bool forceTextResults = false, bool forceBinaryResults = false}) {
    writer.startMessage(bindMessage);

    // Unnamed portal and prepared statement name.
    writer.writeUint8(nullByte);
    writer.writeBytes(_statementNameBytes(query));
    writer.writeUint8(nullByte);

    // Parameters remain text for compatibility. Encoding happens directly
    // into the final message instead of materializing makeParams + spreads.
    writer.writeUint16(0);
    final params = query.preparedParams;
    writer.writeUint16(params.length);
    for (final rawValue in params) {
      final value = _encodeBindValue(rawValue);
      if (value == null) {
        writer.writeInt32(-1);
      } else {
        final encoded = typeConverter.charsetEncode(
            value is String ? value : value.toString(), textCharset);
        writer.writeInt32(encoded.length);
        writer.writeBytes(encoded);
      }
    }

    final columns = query.columns;
    if (forceTextResults && forceBinaryResults) {
      throw ArgumentError(
          'Result formats cannot be forced to text and binary together.');
    }
    if (forceBinaryResults) {
      writer.writeUint16(1);
      writer.writeUint16(1);
    } else if (forceTextResults || columns == null || columns.isEmpty) {
      writer.writeUint16(0);
    } else {
      var binaryCount = 0;
      for (final column in columns) {
        if (column.formatCode == 1) binaryCount++;
      }
      if (binaryCount == 0) {
        writer.writeUint16(0);
      } else if (binaryCount == columns.length) {
        writer.writeUint16(1);
        writer.writeUint16(1);
      } else {
        writer.writeUint16(columns.length);
        for (final column in columns) {
          writer.writeUint16(column.formatCode);
        }
      }
    }
    writer.endMessage();
  }

  Object? _encodeBindValue(Object? value) {
    if (value is double) {
      if (value.isNaN) return 'NaN';
      if (value == double.infinity) return 'Infinity';
      if (value == double.negativeInfinity) return '-Infinity';
    }
    return typeConverter.makeParam(value);
  }

  void _writeExecute(PgWriteBuffer writer) {
    writer.startMessage(executeMessage);
    writer.writeUint8(nullByte);
    writer.writeUint32(0);
    writer.endMessage();
  }

  void _writeEmptyMessage(PgWriteBuffer writer, int code) {
    writer.startMessage(code);
    writer.endMessage();
  }

  int _writePendingStatementCloses(PgWriteBuffer writer) {
    if (_pendingStatementCloses.isEmpty) return 0;
    final count = _pendingStatementCloses.length;
    for (final name in _pendingStatementCloses.values) {
      writer.startMessage(closeMessage);
      writer.writeUint8(statementTarget);
      writer.writeBytes(name);
      writer.writeUint8(nullByte);
      writer.endMessage();
    }
    return count;
  }

  void _sendBuffer(PgWriteBuffer writer, {int statementCloseCount = 0}) {
    _sockWrite(writer.toBytes(copy: false));
    if (statementCloseCount != 0) {
      _maintenanceCloseResponses = statementCloseCount;
      _pendingStatementCloses.clear();
    }
  }

  void _sockWrite(List<int> data) {
    try {
      _socket.add(data);
    } catch (e, s) {
      throw _SocketWriteException('_sockWrite network error $e',
          connectionName: connectionName, cause: e, causeStackTrace: s);
    }
  }

  void _sendStartupMessage() {
    // Int32 - Message length, including self.
    // Int32(196608) - Protocol version number.  Version 3.0.
    // Any number of key/value pairs, terminated by a zero byte:
    //   String - A parameter name (user, database, or options)
    //   String - Parameter value

    final writer = PgWriteBuffer();
    writer.writeUint32(0); // patched after the complete startup packet
    writer.writeInt32(protocol);
    for (var entry in _initParams.entries) {
      writer.writeBytes(
          typeConverter.charsetEncode(entry.key, defaultCodeCharset));
      writer.writeUint8(nullByte);
      writer.writeBytes(entry.value as List<int>);
      writer.writeUint8(nullByte);
    }
    writer.writeUint8(nullByte);
    writer.patchUint32(0, writer.length);

    _sockWrite(writer.toBytes(copy: false));
    _connectionState = ConnectionState.authenticating;
  }

  final PgReadBuffer _buffer = PgReadBuffer();
  int? _msgType;
  int? _msgLength;
  int _maintenanceCloseResponses = 0;
  bool _retryQueryAfterMaintenanceError = false;

  void _readData(Uint8List data) {
    try {
      if (_connectionState == ConnectionState.closed) {
        return;
      }
      _buffer.append(data);

      // Handle resuming after storing message type and length.
      final msgType = _msgType;
      if (msgType != null) {
        final msgLength = _msgLength!;
        if (msgLength > _buffer.bytesAvailable) {
          return;
        }

        _readMessage(msgType, msgLength);

        _msgType = null;
        _msgLength = null;
      }

      // Main message loop.
      while (_connectionState != ConnectionState.closed) {
        if (_buffer.bytesAvailable < 5) return; // Wait for more data.

        // Message length is the message length excluding the message type code, but
        // including the 4 bytes for the length fields. Only the length of the body
        // is passed to each of the message handlers.
        int msgType = _buffer.readByte();
        int length = _buffer.readInt32() - 4;

        if (!_checkMessageLength(msgType, length + 4)) {
          throw PostgresqlException('Lost message sync.',
              connectionName: connectionName);
        }

        if (length > _buffer.bytesAvailable) {
          // Wait for entire message to be in buffer.
          // Store type, and length for when more data becomes available.
          _msgType = msgType;
          _msgLength = length;
          return;
        }

        _readMessage(msgType, length);
      }
    } catch (error, stackTrace) {
      _destroy(reason: error, stackTrace: stackTrace);
    }
  }

  bool _checkMessageLength(int msgType, int msgLength) {
    if (_connectionState == ConnectionState.authenticating) {
      if (msgLength < 8) return false;
      if (msgType == authenticationRequest && msgLength > 2000) return false;
      if (msgType == errorResponse && msgLength > 30000) return false;
    } else {
      if (msgLength < 4) return false;

      // These are the only messages from the server which may exceed 30,000
      // bytes.
      if (msgLength > 30000 &&
          (msgType != noticeResponse &&
              msgType != errorResponse &&
              msgType != copyData &&
              msgType != rowDescription &&
              msgType != parameterDescription &&
              msgType != dataRow &&
              msgType != functionCallResponse &&
              msgType != notificationResponse)) {
        return false;
      }
    }
    return true;
  }

  void _readMessage(int msgType, int length) {
    // DataRow is the dominant message. Pass the socket chunk and offsets
    // directly so the hot path allocates neither a message body nor a view.
    if (msgType == dataRow) {
      if (_buffer.hasContiguous(length)) {
        final bytes = _buffer.currentChunk;
        final offset = _buffer.currentOffset;
        _buffer.skip(length);
        _handleDataRow(bytes, offset, length);
      } else {
        final region = _buffer.readRegion(length);
        _handleDataRow(region.bytes, region.offset, region.length);
      }
      return;
    }

    final region = _buffer.readRegion(length);
    final messageBytes =
        region.offset == 0 && region.length == region.bytes.length
            ? region.bytes
            : Uint8List.sublistView(
                region.bytes, region.offset, region.offset + region.length);
    switch (msgType) {
      case noticeResponse:
        _handleNoticeResponse(messageBytes);
        break;
      case authenticationRequest:
        _handleAuthenticationRequest(messageBytes);
        break;
      case parameterStatus:
        _handleParameterStatus(messageBytes);
        break;
      case backendKeyData:
        _handleBackendKeyData(messageBytes);
        break;
      case readyForQuery:
        _handleReadyForQuery(messageBytes);
        break;
      case errorResponse:
        _handleErrorResponse(messageBytes);
        break;
      case rowDescription:
        _handleRowDescription(messageBytes);
        break;
      case commandComplete:
        _handleCommandComplete(messageBytes);
        break;
      case parseComplete:
        _handleParseComplete(messageBytes);
        break;
      case closeComplete:
        if (_maintenanceCloseResponses > 0) {
          _maintenanceCloseResponses--;
        }
        break;
      case parameterDescription:
        _handleParameterDescription(messageBytes);
        break;
      case notificationResponse:
        _handleNotificationResponse(messageBytes);
        break;
    }
  }

  void _handleParseComplete(List<int> data) {
    // Byte1('1') - Identifier.
    //Int32(4) - Message length, including self.
    _query?.parseComplete = true;
  }

  void _handleParameterDescription(List<int> data) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
  }

  void _handleBackendKeyData(List<int> data) {
    if (data.length != 8) {
      throw FormatException(
          'BackendKeyData body must contain process id and secret key.');
    }
    backendPid = int32FromBytes(data);
    _backendSecretKey = int32FromBytes(data, 4);
    _hasBackendKeyData = true;
  }

  void _handleReadyForQuery(List<int> data) {
    if (data.length != 1) {
      throw FormatException(
          'ReadyForQuery body must contain exactly one status byte.');
    }
    final c = data[0];

    if (c == idleStatus ||
        c == inTransactionStatus ||
        c == inFailedTransactionStatus) {
      if (c == idleStatus) {
        transactionState = TransactionState.none;
      } else if (c == inTransactionStatus) {
        transactionState = TransactionState.begun;
      } else if (c == inFailedTransactionStatus) {
        transactionState = TransactionState.error;
      }

      var was = _connectionState;
      _connectionState = ConnectionState.idle;
      _clearCommandTimers();

      if (was == ConnectionState.authenticated) {
        hasConnected = true;
        _connected.complete(this);
      }

      if (_query != null) {
        final query = _query!;
        if (_retryQueryAfterMaintenanceError) {
          _retryQueryAfterMaintenanceError = false;
          query.resetForRetry();
          _query = null;
          final transaction = query.transactionContext;
          if (transaction == null) {
            _sendQueryQueue.addFirst(query);
          } else {
            transaction.sendQueryQueue.addFirst(query);
          }
          Timer.run(_processSendQueryQueue);
          return;
        }
        final terminalError = query.clientError ?? query.error;
        if (terminalError != null && !query.hasCompletionListener) {
          query.addStreamError(
              terminalError, query.clientStackTrace ?? query.stackTrace);
        }
        query.finish();
        _query = null;
      }

      Timer.run(_processSendQueryQueue);
    } else {
      _destroy();
      throw PostgresqlException(
          'Unknown ReadyForQuery transaction status: ${Utils.itoa(c)}.',
          connectionName: connectionName);
    }
  }

  void _handleRowDescription(Uint8List data) {
    _connectionState = ConnectionState.streaming;
    final query = _query!;
    final requireBinaryResults = query.requireBinaryResults;
    final byteData = ByteData.sublistView(data);
    final count = byteData.getUint16(0, Endian.big);
    var idx = 2;

    var list = <ColumnDescription>[];

    for (var i = 0; i < count; i++) {
      final nameEnd = data.indexOf(nullByte, idx);
      if (nameEnd < 0) {
        throw const FormatException('Unterminated RowDescription name.');
      }
      final name = Uint8List.sublistView(data, idx, nameEnd);
      idx = nameEnd + 1;
      if (idx + 18 > data.length) {
        throw const FormatException('Truncated RowDescription field.');
      }
      final tableOid = byteData.getUint32(idx, Endian.big);
      final columnAttrnum = byteData.getInt16(idx + 4, Endian.big);
      final typeOid = byteData.getUint32(idx + 6, Endian.big);
      final typeSize = byteData.getInt16(idx + 10, Endian.big);
      final typeModifier = byteData.getInt32(idx + 12, Endian.big);
      final describedFormatCode = byteData.getUint16(idx + 16, Endian.big);
      // Describe Statement precedes Bind and therefore reports text even when
      // this execution's portal requested binary for every result column.
      final formatCode = requireBinaryResults ? 1 : describedFormatCode;
      String fieldName = typeConverter.charsetDecode(name, textCharset);
      idx += 18;

      list.add(ColumnDescription(i, fieldName, tableOid, columnAttrnum, typeOid,
          typeSize, typeModifier, formatCode));
    }

    if (idx != data.length) {
      throw FormatException(
          'RowDescription contains ${data.length - idx} trailing bytes.');
    }

    query.columnCount = count;
    final schema = ResultSchema.fromColumns(list, typeConverter);
    if (query.requireBinaryResults && !schema.supportsAllBinary) {
      query.clientError = _unsupportedBinaryResultsError(schema);
      query.clientStackTrace = StackTrace.current;
      query.dataRowSink = null;
    }
    query.resultSchema = schema;
    query.columns = schema.columns;
  }

  UnsupportedError _unsupportedBinaryResultsError(ResultSchema schema) {
    final oids = schema.unsupportedBinaryOids.join(', ');
    return UnsupportedError(
        'Strict binary results are unavailable because PostgreSQL result '
        'OID(s) [$oids] do not have complete binary decoders.');
  }

  void _handleDataRow(Uint8List data, int offset, int length) {
    final query = _query!;
    if (query.clientError != null) return;

    final schema = query.resultSchema;
    if (schema == null) {
      query.clientError = StateError('DataRow received without a schema.');
      query.clientStackTrace = StackTrace.current;
      return;
    }

    try {
      final sink = query.dataRowSink;
      if (sink != null) {
        sink(data, offset, length);
        query.rowCount++;
      } else {
        query.addRow(
            schema.decodeRow(data, baseOffset: offset, messageLength: length));
      }
    } catch (error, stackTrace) {
      // A mapper/converter failure does not desynchronize the protocol: the
      // complete DataRow body is already delimited. Drain remaining messages
      // and report the error when ReadyForQuery arrives.
      query.clientError = error;
      query.clientStackTrace = stackTrace;
      query.dataRowSink = null;
    }
  }

  void _handleCommandComplete(List<int> data) {
    final query = _query;

    var rowsAffected = 0;
    var multiplier = 1;
    var cursor = data.length - 2; // final byte is the C-string terminator
    while (cursor >= 0) {
      final digit = data[cursor] - 0x30;
      if (digit < 0 || digit > 9) break;
      rowsAffected += digit * multiplier;
      multiplier *= 10;
      cursor--;
    }
    if (query != null) {
      query.rowsAffected.value = rowsAffected;
    }
  }

  void _sendMessage(int code, List<int> bytes) {
    try {
      final writer = PgWriteBuffer(initialCapacity: bytes.length + 5);
      writer.startMessage(code);
      writer.writeBytes(bytes);
      writer.endMessage();
      _sockWrite(writer.toBytes(copy: false));
    } catch (e) {
      throw PostgresqlException("_sendMessage connection is closed $e",
          connectionName: connectionName);
    }
  }

  void _handleNoticeResponse(List<int> data) {
    final map = <String, String>{};
    var offset = 0;
    while (offset < data.length && data[offset] != nullByte) {
      final key = String.fromCharCode(data[offset++]);
      final end = data.indexOf(nullByte, offset);
      if (end < 0) throw const FormatException('Unterminated NoticeResponse.');
      map[key] =
          typeConverter.charsetDecode(data.sublist(offset, end), textCharset);
      offset = end + 1;
    }
    final msg = ServerNotice(false, map, connectionName);
    if (!_notices.isClosed) _notices.add(msg);
  }

  void _handleNotificationResponse(List<int> data) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    var backendPid = int32FromBytes(data);
    var idx = 4;
    var nullIndex = data.indexOf(nullByte, idx);

    var channel =
        typeConverter.charsetDecode(data.sublist(idx, nullIndex), textCharset);
    var payload = typeConverter.charsetDecode(
        data.sublist(nullIndex + 1, data.length - 1), textCharset);
    _notifications.add(
        {'backendPid': backendPid, 'channel': channel, 'payload': payload});
  }

  void _handleAuthenticationRequest(List<int> data) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html

    if (_connectionState != ConnectionState.authenticating) {
      throw PostgresqlException(
          'Invalid connection state while authenticating.',
          connectionName: connectionName);
    }
    final authCode = int32FromBytes(data);
    authenticationRequestType = AuthenticationRequestType.fromCode(authCode);

    if (authenticationRequestType == AuthenticationRequestType.ok) {
      _connectionState = ConnectionState.authenticated;
      return;
    } else if (authenticationRequestType ==
        AuthenticationRequestType.cleartextPassword) {
      if (password == null) {
        throw PostgresqlException(
            'server requesting cleartext password authentication, but no password was provided',
            connectionName: connectionName);
      }
      _sendMessage(passwordMessage, [...passwordBytes, nullByte]);
    } else if (authenticationRequestType ==
        AuthenticationRequestType.md5Password) {
      if (password == null) {
        throw PostgresqlException(
            'server requesting MD5 password authentication, but no password  was provided',
            connectionName: connectionName);
      }
      var salt = data.sublist(4, 8);
      var pwd = [
        ...'md5'.codeUnits,
        ...typeConverter.charsetEncode(
            Utils.md5HexString([
              ...typeConverter.charsetEncode(
                  Utils.md5HexString([...passwordBytes, ...userBytes]),
                  defaultCodeCharset),
              ...salt
            ]),
            defaultCodeCharset)
      ];

      _sendMessage(passwordMessage, [...pwd, nullByte]);
    } else if (authenticationRequestType == AuthenticationRequestType.sasl) {
      if (password == null) {
        throw PostgresqlException(
          'Server requested SASL authentication, but no password was provided.',
          connectionName: connectionName,
        );
      }
      final mechanisms = <String>[];
      var offset = 4;
      while (offset < data.length && data[offset] != nullByte) {
        final end = data.indexOf(nullByte, offset);
        if (end < 0) {
          throw const FormatException('Unterminated SASL mechanism.');
        }
        mechanisms.add(typeConverter.charsetDecode(
            data.sublist(offset, end), defaultCodeCharset));
        offset = end + 1;
      }
      if (mechanisms.isEmpty) {
        throw PostgresqlException('Server supplied no SASL mechanism.',
            connectionName: connectionName);
      }
      const selectedMechanism = 'SCRAM-SHA-256';
      if (!mechanisms.contains(selectedMechanism)) {
        throw PostgresqlException(
          'Server does not offer the supported SASL mechanism '
          '$selectedMechanism (offered: ${mechanisms.join(', ')}).',
          connectionName: connectionName,
        );
      }

      scramAuthenticator = ScramAuthenticator(
        selectedMechanism,
        sha256,
        UsernamePasswordCredential(username: user, password: password),
      );

      var init = scramAuthenticator!.handleMessage(
            SaslMessageType.authenticationSasl,
            Uint8List.fromList([]),
            specifyUsername: true,
          );

      var mech = [
        ...typeConverter.charsetEncode(
            scramAuthenticator!.mechanism.name, defaultCodeCharset),
        nullByte
      ];
      var saslInitialResponse = [
        ...mech,
        ...int32Bytes(init?.length ?? 0),
        ...init!
      ];
      _sendMessage(passwordMessage, saslInitialResponse);
    } else if (authenticationRequestType ==
        AuthenticationRequestType.saslContinue) {
      var msg = scramAuthenticator!.handleMessage(
            SaslMessageType.authenticationSaslContinue,
            Uint8List.fromList(data.sublist(4)),
          );
      _sendMessage(passwordMessage, msg!);
    } else if (authenticationRequestType ==
        AuthenticationRequestType.saslFinal) {
      scramAuthenticator!.handleMessage(
            SaslMessageType.authenticationSaslFinal,
            Uint8List.fromList(data.sublist(4)),
          );
      //2=KerberosV5, 4=CryptPassword, 6=SCMCredential, 7=GSS, 8=GSSContinue, 9=SSPI
    } else if ([2, 4, 6, 7, 8, 9].contains(authCode)) {
      throw PostgresqlException(
          'Authentication method $authCode not supported.',
          connectionName: connectionName);
    } else {
      throw PostgresqlException(
          'Authentication method $authCode not recognized.',
          connectionName: connectionName);
    }
  }

  void _handleParameterStatus(List<int> data) {
    var pos = data.indexOf(nullByte);
    var key =
        typeConverter.charsetDecode(data.sublist(0, pos), defaultCodeCharset);
    var value = typeConverter.charsetDecode(
        data.sublist(pos + 1, data.length - 1), textCharset);
    serverInfo.rawParams[key] = value;

    if (key == 'client_encoding' && value != 'UTF8') {
      var msg =
          '''client_encoding parameter must remain as UTF8 for correct string
          handling. client_encoding is: "$value".''';
      if (_notices.isClosed == false) {
        _notices.add(ClientNotice(
            severity: 'WARNING', message: msg, connectionName: connectionName));
      }
    }

    switch (key.toLowerCase()) {
      case 'client_encoding':
        serverInfo.clientEncoding = value;
        break;
      case 'datestyle':
        serverInfo.dateStyle = value;
        break;
      case 'integer_datetimes':
        serverInfo.integerDatetimes = value;
        break;
      case 'is_superuser':
        serverInfo.isSuperuser = value;
        break;
      case 'server_encoding':
        serverInfo.serverEncoding = value;
        break;
      case 'server_version':
        serverInfo.serverVersion = value;
        break;
      case 'session_authorization':
        serverInfo.sessionAuthorization = value;
        break;
      case 'standard_conforming_strings':
        serverInfo.standardConformingStrings = value;
        break;
      case 'timezone':
        timeZone = serverInfo.timeZone.copyWith(value: value);
        serverInfo.timeZone = timeZone;
        break;
    }
  }

  void _handleSocketError(dynamic error, {bool closed = false}) {
    if (_connectionState == ConnectionState.closed) {
      return;
    }
    final message = closed ? 'Socket closed unexpectedly.' : 'Socket error.';
    final exception = PostgresqlException(message,
        errorCode: error, connectionName: connectionName, sql: _query?.getSql);

    if (!hasConnected && !_connected.isCompleted) {
      _connected.completeError(exception);
    } else if (_query == null && !_notices.isClosed) {
      _notices.add(ClientNotice(
          isError: true,
          connectionName: connectionName,
          severity: 'ERROR',
          message: message,
          exception: error));
    }
    _destroy(reason: exception);
  }

  void _handleSocketClosed() {
    if (_connectionState != ConnectionState.closed) {
      _handleSocketError(null, closed: true);
    }
  }

  void _handleErrorResponse(List<int> data) {
    if (_maintenanceCloseResponses > 0 && _query != null) {
      _maintenanceCloseResponses = 0;
      _retryQueryAfterMaintenanceError = true;
      return;
    }
    final map = <String, String>{};
    var offset = 0;
    while (offset < data.length && data[offset] != nullByte) {
      final key = String.fromCharCode(data[offset++]);
      final end = data.indexOf(nullByte, offset);
      if (end < 0) {
        throw const FormatException('Unterminated ErrorResponse field.');
      }
      final field = data.sublist(offset, end);
      try {
        map[key] = typeConverter.charsetDecode(field, textCharset);
      } on FormatException {
        // Authentication errors can arrive before PostgreSQL applies the
        // requested client_encoding. Never let a diagnostic break connect().
        map[key] = utf8.decode(field, allowMalformed: true);
      }
      offset = end + 1;
    }

    var msg = ServerNotice(true, map, connectionName);
    lastServerNotice = msg;

    var postgresqlException = PostgresqlException(
      msg.message,
      connectionName: connectionName,
      serverMessage: msg,
      errorCode: msg.code,
      serverErrorCode: msg.code,
      sql: _query?.getSql,
    );

    if (!hasConnected) {
      _connected.completeError(postgresqlException);
      _destroy(reason: postgresqlException, terminal: !allowAttemptToReconnect);
    } else {
      _query?.error = postgresqlException;
      if (msg.code == '26000' || msg.code == '0A000') {
        _invalidateCachedStatement(_query, closeOnServer: msg.code != '26000');
      }
      if (msg.code?.startsWith('57P') ?? false) {
        _destroy(reason: postgresqlException);
      }
    }
  }

  @override
  Future<void> close() {
    final closing = _closeOperation;
    if (closing != null) return closing;
    if (_terminallyClosed) {
      if (!_notices.isClosed) _notices.close();
      if (!_notifications.isClosed) _notifications.close();
      return Future<void>.value();
    }

    _terminallyClosed = true;
    _lifecycleGeneration++;
    _connectionState = ConnectionState.closed;
    hasConnected = false;
    final operation = _closeTerminally();
    _closeOperation = operation;
    return operation;
  }

  Future<void> _closeTerminally() async {
    final closeError = PostgresqlException(
        'Connection closed before query could complete',
        connectionName: connectionName);

    try {
      if (_hasSocket) {
        _sockWrite(terminateMessage);
        await _socket.flush();
      }
    } catch (e, st) {
      if (!_notices.isClosed) {
        _notices.add(ClientNotice(
            severity: 'WARNING',
            message:
                'Exception while closing connection. Closed without sending '
                'terminate message.',
            connectionName: connectionName,
            exception: e,
            stackTrace: st));
      }
    } finally {
      _destroy(reason: closeError, terminal: true);
    }
  }

  void _destroy(
      {Object? reason, StackTrace? stackTrace, bool terminal = false}) {
    final error = reason ??
        PostgresqlException('Connection closed.',
            connectionName: connectionName);
    if (!_connected.isCompleted) {
      _connected.completeError(error, stackTrace ?? StackTrace.current);
    }
    hasConnected = false;
    _connectionState = ConnectionState.closed;
    _clearCommandTimers();
    backendPid = 0;
    _backendSecretKey = 0;
    _hasBackendKeyData = false;
    if (terminal) {
      _terminallyClosed = true;
      _lifecycleGeneration++;
    }
    _socketGeneration++;
    final subscription = _socketSubscription;
    _socketSubscription = null;
    subscription?.cancel();

    final active = _query;
    _query = null;
    if (active != null) _failQuery(active, error, stackTrace);
    while (_sendQueryQueue.isNotEmpty) {
      _failQuery(_sendQueryQueue.removeFirst(), error, stackTrace);
    }
    final currentTransaction = _currentTransaction;
    _currentTransaction = null;
    if (currentTransaction != null) {
      currentTransaction.markFailed(error);
      while (currentTransaction.sendQueryQueue.isNotEmpty) {
        _failQuery(
            currentTransaction.sendQueryQueue.removeFirst(), error, stackTrace);
      }
    }
    while (_transactionQueue.isNotEmpty) {
      final transaction = _transactionQueue.removeFirst();
      transaction.markFailed(error);
      while (transaction.sendQueryQueue.isNotEmpty) {
        _failQuery(transaction.sendQueryQueue.removeFirst(), error, stackTrace);
      }
    }

    for (final preparation in _statementPreparations.values) {
      if (!preparation.isCompleted) preparation.complete();
    }
    _statementPreparations.clear();
    clearStatementCache(closeStatements: false);
    _statementUseCounts.clear();
    _buffer.clear();
    _msgType = null;
    _msgLength = null;
    _maintenanceCloseResponses = 0;
    _retryQueryAfterMaintenanceError = false;

    if (_hasSocket) {
      _socket.destroy();
      _hasSocket = false;
    }
    final openingSocket = _openingSocket;
    _openingSocket = null;
    openingSocket?.destroy();
    if (terminal || !allowAttemptToReconnect) {
      if (!_notices.isClosed) _notices.close();
      if (!_notifications.isClosed) _notifications.close();
    }
  }

  void _invalidateCachedStatement(Query? query, {required bool closeOnServer}) {
    if (query == null) return;
    final cached = _statementCache[query.getSql];
    if (cached == null || cached.statementName != query.statementName) return;
    _statementCache.remove(query.getSql);
    statementCacheInvalidations++;
    if (closeOnServer) {
      _scheduleStatementClose(cached);
    }
  }

  void _failQuery(Query query, Object error, [StackTrace? stackTrace]) {
    if (query.streamIsClosed) return;
    query.clientError ??= error;
    query.clientStackTrace ??= stackTrace;
    if (!query.hasCompletionListener) {
      query.addStreamError(error, stackTrace);
    }
    query.finish();
  }
}

class _SocketWriteException extends PostgresqlException {
  final Object cause;
  final StackTrace? causeStackTrace;

  _SocketWriteException(super.message,
      {required super.connectionName,
      required this.cause,
      this.causeStackTrace})
      : super(errorCode: cause);
}

