// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:collection';

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'execution_context.dart';
import 'results.dart';

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
import 'pack_unpack.dart';
import 'query.dart';
import 'server_info.dart';
import 'server_notice.dart';
import 'ssl_context.dart';

import 'transaction_context.dart';
import 'utils/buffer.dart';
import 'connection_state.dart';

import 'transaction_state.dart';

class CoreConnection implements ExecutionContext {
  late List<int> userBytes;
  String? host;
  String? database;
  int port;
  late List<int> passwordBytes;
  String sourceAddress;
  bool isUnixSocket = false;
  //SSLv3/TLS TLSv1.3
  SslContext? sslContext;

  bool tcpKeepalive;
  String? applicationName;
  dynamic replication;
  // for SCRAM-SHA-256 auth
  ScramAuthenticator? scramAuthenticator;
  late AuthenticationRequestType authenticationRequestType;

  /// The owner of the connection, or null if not available.
  ConnectionOwner? owner;

  String? connectionName;
  int connectionId = 0;

  late Completer<CoreConnection> _connected; // = Completer<CoreConnection>();

  // PreparedStatementState _preparedStatementState = PreparedStatementState.none;

  //bool autocommit = false;
  //dynamic _xid;
  //Set _statement_nums;

  Socket? _socket;
  //client_encoding
  //String clientEncoding = 'utf8';

  String defaultCodeCharset = 'ascii'; //ascii
  String textCharset = 'utf8'; //utf8

  late TypeConverter typeConverter;

   /// default query Timeout =  300 seconds
  static const defaultTimeout = const Duration(seconds: 300);

  // var _commands_with_count = [
  //   "INSERT".codeUnits,
  //   "DELETE".codeUnits,
  //   "UPDATE".codeUnits,
  //   "MOVE".codeUnits,
  //   "FETCH".codeUnits,
  //   "COPY".codeUnits,
  //   "SELECT".codeUnits,
  // ];

  StreamController _notifications = StreamController<dynamic>.broadcast();
  Stream<dynamic> get notifications => _notifications.stream;

  StreamController _notices = StreamController<dynamic>.broadcast();
  Stream<dynamic> get notices => _notices.stream;

  //Map<String, dynamic> serverParameters = <String, dynamic>{};

  ServerInfo serverInfo = ServerInfo();

  String user;
  String? password;

  Duration connectionTimeout = Duration(seconds: 180);

  ServerNotice? lastServerNotice;

  ///  Int32(196608) - Protocol version number.  Version 3.0.
  int protocol = 196608;

  Map<String, dynamic> _initParams = <String, dynamic>{};

  List<int>? _transaction_status;

  ConnectionState _connectionState = ConnectionState.notConnected;

  /// connection  is Closed
  bool get isClosed =>
      _connectionState == ConnectionState.closed ||
      _connectionState == ConnectionState.notConnected;

  ConnectionState get connectionState => _connectionState;

  /// experimental: allow reconnection attempt in case of posgresql server restart
  bool allowAttemptToReconnect = false;
  int _tryReconnectCount = 0;
  int tryReconnectLimit = 20;

  TransactionState transactionState = TransactionState.unknown;

  //late Buffer _buffer;
  // backend_key_data
  int backendPid = 0;

  bool hasConnected = false;
  // queue of queries to be executed
  Queue<Query> _sendQueryQueue = Queue<Query>();

  /// size of Query Queue
  int get queryQueueSize => _sendQueryQueue.length;
  Query? _query;

  int prepareStatementId = 0;
  //int _transactionLevel = 0;

  // transaction queue to be executed
  Queue<TransactionContext> _transactionQueue = Queue<TransactionContext>();

  /// size of Query Queue
  int get transactionQueueSize => _transactionQueue.length;

  TransactionContext? _currentTransaction;
  int _transactionId = 0;

  /// [textCharset] utf8 | latin1 | ascii
  /// [host] ip, dns or unix socket
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
    this.tcpKeepalive = false,
    this.applicationName,
    this.replication = null,
    this.connectionName,
    this.textCharset = 'utf8',
    this.allowAttemptToReconnect = false,
  }) {
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
      tcpKeepalive: settings.tcpKeepalive,
      applicationName: settings.applicationName,
      replication: settings.replication,
      connectionName: settings.connectionName,
      textCharset: settings.textCharset,
      allowAttemptToReconnect: settings.allowAttemptToReconnect,
    );
  }

  /// Create Connection from uri
  /// Example:  var uri = 'postgres://postgres:s1sadm1n@localhost:5432/sistemas';
  /// var con = CoreConnection.fromUri(uri);
  factory CoreConnection.fromUri(String uriString) {
    var settings = ConnectionSettings.fromUri(uriString);
    return CoreConnection.fromSettings(settings);
  }

  void _init() {
    // if (user == null) {
    //   throw PostgresqlException(
    //       "The 'user' connection parameter cannot be null",
    //       connectionName: connectionName);
    // }

    if (connectionName == null) {
      connectionName = 'dargres_$connectionId';
    }

    _initParams = <String, dynamic>{
      "user": user,
      "database": database,
      "application_name": applicationName,
      "replication": replication,
    };

    var init_params_entries = [..._initParams.entries];
    for (var entry in init_params_entries) {
      if (entry.value is String) {
        _initParams[entry.key] =
            typeConverter.charsetEncode(entry.value, textCharset);
      } else if (entry.value == null) {
        _initParams.remove(entry.key);
      }
    }

    //_buffer = Buffer();

    this.userBytes = _initParams['user'];

    if (password is String) {
      this.passwordBytes = typeConverter.charsetEncode(password!, textCharset);
    }
  }

  void _setKeepAlive() {
    //print('CoreConnection@_setKeepAlive start');
    RawSocketOption option;
    if (Platform.isAndroid || Platform.isLinux) {
      option =
          RawSocketOption.fromBool(LINUX_SOL_SOCKET, LINUX_SO_KEEPALIVE, true);
    } else {
      option = RawSocketOption.fromBool(
          WINDOWS_SOL_SOCKET, WINDOWS_SO_KEEPALIVE, true);
    }
    _socket?.setRawOption(option);
  }

  /// [delayBeforeConnect] in seconds
  Future<CoreConnection> connect(
      {int? delayBeforeConnect, int? delayAfterConnect}) async {
    //print('CoreConnection@connect start');
    // reset all
    hasConnected = false;
    _sendQueryQueue = Queue<Query>();
    _query = null;
    prepareStatementId = 0;
    _transactionQueue = Queue<TransactionContext>();
    _currentTransaction = null;
    _transactionId = 0;
    transactionState = TransactionState.unknown;
    _transaction_status = null;
    _notifications = StreamController<dynamic>.broadcast();
    _notices = StreamController<dynamic>.broadcast();
    lastServerNotice = null;
    scramAuthenticator = null;
    // reset all

    _connectionState = ConnectionState.socketConnecting;

    if (delayBeforeConnect != null) {
      await Future.delayed(Duration(seconds: delayBeforeConnect));
    }

    _connected = Completer<CoreConnection>();
    if (isUnixSocket == false && host != null) {
      try {
        _socket = await Socket.connect(host, port).timeout(connectionTimeout);
      } catch (e) {
        _connectionState = ConnectionState.closed;
        //tenta se reconectar
        // if (_tryReconnectCount <= tryReconnectLimit &&
        //     allowAttemptToReconnect == true) {
        //   tryReconnect();
        // } else {
        //   throw PostgresqlException(
        //       """Can't create a connection to host $host and port $port
        //             (timeout is: $connectionTimeout and sourceAddress is: $sourceAddress).""",
        //       connectionName: connectionName);
        // }
        //print('Can\'t create a connection to host');
        throw PostgresqlException(
            """Can't create a connection to host $host and port $port 
                     (timeout is: $connectionTimeout and sourceAddress is: $sourceAddress).""",
            connectionName: connectionName);
      }
    } else if (isUnixSocket == true) {
      //throw UnimplementedError('unix_sock not implemented');
      _socket = await Socket.connect(
              InternetAddress(host!, type: InternetAddressType.unix), port)
          .timeout(connectionTimeout);
    } else {
      //print('one of host or unix_sock must be provided');
      _connectionState = ConnectionState.closed;
      throw PostgresqlException('one of host or unix_sock must be provided',
          connectionName: connectionName);
    }

    if (sslContext != null) {
      _socket = await _connectSsl();
    }

    if (tcpKeepalive == true) {
      _setKeepAlive();
    }

    _connectionState = ConnectionState.socketConnected;

    _tryReconnectCount = 0;
    connectionId++;

    this._socket?.listen(_readData,
        onError: _handleSocketError, onDone: _handleSocketClosed);
    _sendStartupMessage();

    if (delayAfterConnect != null) {
      await Future.delayed(Duration(seconds: delayAfterConnect));
    }
   // print('CoreConnection@connect _socket conected');
    return _connected.future;
  }

  Future<SecureSocket> _connectSsl() async {
    var future = Socket.connect(host, port, timeout: connectionTimeout);
    var completer = Completer<SecureSocket>();

    future.then((socket) {
      socket.listen((data) {
        if (data[0] != STATEMENT) {
          socket.destroy();
          completer.completeError(PostgresqlException(
            'This postgresql server is not configured to support SSL '
            'connections.',
            connectionName: connectionName,
          ));
        } else {
          SecurityContext();
          SecureSocket.secure(
            socket,
            context: sslContext!.context,
            onBadCertificate: sslContext!.onBadCertificate,
            // keyLog: sslContext.keyLog,
            supportedProtocols: sslContext!.supportedProtocols,
          ).then(completer.complete).catchError(completer.completeError);
        }
      });

      // Write header, and SSL magic number.
      socket.add(const [0, 0, 0, 8, 4, 210, 22, 47]);
    }).catchError((ex, st) {
      completer.completeError(ex, st);
    });

    return completer.future;
  }

  /// Execute a sql command e return affected row count
  /// Example: con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;')
  Future<int> execute(String sql, {Duration? timeout}) async {
    try {
      var query = Query(sql);
      query.state = QueryState.init;
      query.queryType = QueryType.simple;
      await _enqueueQuery(query);

      if (timeout != null) {
        await query.stream.toList().timeout(timeout);
      } else {
        await query.stream.toList();
      }

      return query.rowsAffected.value;
    } catch (ex, st) {
      return Future.error(ex, st);
    }
  }

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  Future<Results> querySimple(String sql, {Duration? timeout}) async {
    //print('CoreConnection@querySimple start');
    var streamResp = await querySimpleAsStream(sql);
    if (timeout != null) {
      return streamResp.toResults().timeout(timeout);
    }
    return streamResp.toResults();
  }

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  Future<ResultStream> querySimpleAsStream(String sql) async {
    //print('CoreConnection@querySimpleAsStream start');
    // try {
    // if (params != null) {
    //   statement = substitute(statement, params, typeConverter.encodeValue);
    // }

    var query = Query(sql);
    query.state = QueryState.init;
    query.queryType = QueryType.simple;
    await _enqueueQuery(query);
    var resultStream = query.stream;
    resultStream.rowsAffected = query.rowsAffected;
    return resultStream;
    //} catch (ex, st) {
    //  return ResultStream.fromFuture(Future.error(ex, st));
    //}
  }

  /// execute a prepared unnamed statement
  /// [isDeallocate] = if isDeallocate == true execute DEALLOCATE command on end of query execution
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example: com.queryUnnamed(r'select * from crud_teste.pessoas limit $1', [1]);
  Future<Results> queryUnnamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false,
      Duration? timeout}) async {
    //print('CoreConnection@queryUnnamed start');
    if (timeout != null) {
      var statement = await prepareStatement(sql, params,
          isUnamedStatement: true,
          placeholderIdentifier: placeholderIdentifier,
          timeout: timeout);

      var result = await executeStatement(statement,
          isDeallocate: isDeallocate, timeout: timeout);
      return result;
    } else {
      var statement = await prepareStatement(sql, params,
          isUnamedStatement: true,
          placeholderIdentifier: placeholderIdentifier);
      var result =
          await executeStatement(statement, isDeallocate: isDeallocate);
      return result;
    }
  }

  /// execute a prepared named statement
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example: com.queryUnnamed(r'select * from crud_teste.pessoas limit $1', [1]);
  Future<Results> queryNamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false,
      Duration? timeout}) async {
    if (timeout != null) {
      var statement = await prepareStatement(sql, params,
              isUnamedStatement: false,
              placeholderIdentifier: placeholderIdentifier)
          .timeout(timeout);

      var result = await executeStatement(statement, isDeallocate: isDeallocate)
          .timeout(timeout);
      return result;
    } else {
      var statement = await prepareStatement(sql, params,
          isUnamedStatement: false,
          placeholderIdentifier: placeholderIdentifier);
      var result =
          await executeStatement(statement, isDeallocate: isDeallocate);
      return result;
    }
  }

  /// prepare statement
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example:
  /// var statement = await prepareStatement('SELECT * FROM table LIMIT $1', [0]);
  /// var result await executeStatement(statement);
  Future<Query> prepareStatement(
    String sql,
    dynamic params, {
    bool isUnamedStatement = false,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    Duration? timeout,
  }) async {
    //print('CoreConnection@prepareStatement start');
    var query = Query(sql,
        params: params, placeholderIdentifier: placeholderIdentifier);

    query.state = QueryState.init;
    query.connection = this;
    query.error = null;
    query.isUnamedStatement = isUnamedStatement;
    query.prepareStatementId = prepareStatementId;
    prepareStatementId++;
    query.queryType = QueryType.prepareStatement;
    await _enqueueQuery(query);

    if (timeout != null) {
      await query.stream.toList().timeout(timeout);
    } else {
      await query.stream.toList();
    }

    return query;
  }

  /// run prepared query with (prepareStatement) method and return List of Row
  Future<Results> executeStatement(Query query,
      {bool isDeallocate = false, Duration? timeout}) async {
    //print('CoreConnection@executeStatement start');
    if (timeout != null) {
      var stm = await executeStatementAsStream(query).timeout(timeout);
      var result = stm.toResults().timeout(timeout);
      if (isDeallocate == true) {
        await execute('DEALLOCATE ${query.statementName}', timeout: timeout);
      }
      return result;
    } else {
      var stm = await executeStatementAsStream(query);
      var result = stm.toResults();
      if (isDeallocate == true) {
        await execute('DEALLOCATE ${query.statementName}');
      }
      return result;
    }
  }

  /// run Query prepared with (prepareStatement) method
  Future<ResultStream> executeStatementAsStream(Query query) async {
    //print('CoreConnection@executeStatementAsStream start');
    //try {
    //cria uma copia
    var newQuery = query; //query.clone();
    newQuery.error = null;
    newQuery.state = QueryState.init;
    newQuery.reInitStream();
    newQuery.queryType = QueryType.execStatement;
    await _enqueueQuery(newQuery);
    return newQuery.stream;
    // } catch (ex, st) {
    //   return ResultStream.fromFuture(Future.error(ex, st));
    //}
  }

  Future<TransactionContext> beginTransaction({Duration? timeout}) async {
    var transaction = TransactionContext(_transactionId, this);
   // print('CoreConnection@beginTransaction start');
    //'START TRANSACTION'
    final commandBegin = 'BEGIN';
    await _enqueueTransaction(transaction);
    await transaction.execute(commandBegin, timeout: timeout);
    _transactionId++;
    return transaction;
  }

  Future<void> rollBack(TransactionContext transaction,
      {Duration? timeout}) async {
    //print('CoreConnection@rollBack start');
    await transaction.execute('ROLLBACK', timeout: timeout);
    //if (transaction == _currentTransaction)
    //print('rollBack id ${_currentTransaction?.transactionId}');
    _currentTransaction = null;
    //print('rollBack $_currentTransaction');
  }

  Future<void> commit(TransactionContext transaction,
      {Duration? timeout}) async {
    //print('CoreConnection@commit start');
    await transaction.execute('COMMIT', timeout: timeout);
    // if (transaction == _currentTransaction)
    //print('commit id ${_currentTransaction?.transactionId}');
    _currentTransaction = null;
    // print('commit $_currentTransaction');
  }

  /// execute querys in transaction
  Future<T> runInTransaction<T>(
    Future<T> operation(TransactionContext ctx), {
    Duration? timeout,
    Duration? timeoutInner,
  }) async {
    //print('CoreConnection@runInTransaction start');
    final transa = await beginTransaction();
    //print('runInTransaction Id:${transa.transactionId}');
    try {
      var result;
      if (timeoutInner != null) {
        result = await operation(transa).timeout(timeoutInner);
      } else {
        result = await operation(transa);
      }
      await commit(transa, timeout: timeout);
      return result;
    } catch (e) {
      //print('runInTransaction catch (_)');
      //print('runInTransaction  $e $s');
      await rollBack(transa, timeout: timeout);
      rethrow;
    }
  }

  Future<void> _enqueueTransaction(TransactionContext transaction) async {
    //print('CoreConnection@_enqueueTransaction start');
    if (_connectionState == ConnectionState.notConnected) {
      throw PostgresqlException(
          'Connection is notConnected, cannot execute query.',
          errorCode: 501);
    }
    if (_connectionState == ConnectionState.closed) {
      if (_tryReconnectCount <= tryReconnectLimit &&
          allowAttemptToReconnect == true) {
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
    // print('_enqueueTransaction id: ${transaction.transactionId}');
    _transactionQueue.addLast(transaction);

    if (_connectionState == ConnectionState.socketConnecting) {
      // print('_enqueueTransaction: aguarda Reconnect pois esta fazendo conexão agora');
      await waitReconnect();
    }

    Timer.run(_processTransactionQueue);
  }

  void _processTransactionQueue() async {
    //print('CoreConnection@_processTransactionQueue start');
    if (_transactionQueue.isEmpty) {
      //print('_processTransactionQueue _transactionQueue.isEmpty');
      return;
    }
    if (_currentTransaction != null) {
      //print('_processTransactionQueue _currentTransaction != null');
      return;
    }
    if (_connectionState != ConnectionState.idle) {
      //print('_processTransactionQueue state != ConnectionState.idle');
      return;
    }
    _currentTransaction = _transactionQueue.removeFirst();
    // print('_processTransactionQueue ${_currentTransaction.transactionId}');
    Timer.run(_processSendQueryQueue);
  }

  /// coloca a query na fila
  Future<void> _enqueueQuery(Query query) async {
    //print(  'CoreConnection@_enqueueQuery start _connectionState ${_connectionState}');

    if (_connectionState == ConnectionState.notConnected) {
      throw PostgresqlException(
          'Connection is notConnected, cannot execute query.',
          errorCode: 501);
    }
    if (_connectionState == ConnectionState.closed) {
      if (_tryReconnectCount <= tryReconnectLimit &&
          allowAttemptToReconnect == true) {
       // print('_enqueueQuery tenta se reconectar ');
        await tryReconnect();
      } else {
        throw PostgresqlException('Connection is closed, cannot execute query.',
            errorCode: 500, //57P01
            serverMessage: lastServerNotice,
            connectionName: connectionName,
            serverErrorCode: lastServerNotice?.code);
      }
    }

    //print('_enqueueQuery add Query ');
    query.state = QueryState.queued;
    _sendQueryQueue.addLast(query);

    if (_connectionState == ConnectionState.socketConnecting) {
      //print('CoreConnection@_enqueueQuery: aguarda Reconnect pois esta fazendo conexão agora');
      await waitReconnect();
    }

    Timer.run(_processSendQueryQueue);
  }

  Future<void> waitReconnect() async {
    //print('CoreConnection@waitReconnect start');
    var completer = Completer();
    Timer.periodic(Duration(milliseconds: 900), (timer) async {
     // print('waitReconnect: aguardando reconectar');
      if (_connectionState != ConnectionState.socketConnecting) {
        // print('waitReconnect: _connectionState ${_connectionState}');
        timer.cancel();
        completer.complete();
      }
    });
    await completer.future;
  }

  ///
  Future<void> tryReconnect() async {
    //print('tryReconnect inicio: _connectionState ${_connectionState}');
    await close();
    await Future.delayed(Duration(seconds: 1));
    // if (_connectionState == ConnectionState.clossing) {
    //   print(
    //       'tryReconnect: não tenta reconectar esta fechando conexão agora');
    //   return;
    // }
    if (_connectionState == ConnectionState.socketConnecting) {
    //  print( 'tryReconnect: não tenta reconectar pois esta fazendo conexão agora');
      //return await waitReconnect();
      return;
    }
    if (_connectionState == ConnectionState.authenticating) {
     // print( 'tryReconnect: não tenta reconectar pois esta authenticating agora');
      return;
    }

    if (_tryReconnectCount > tryReconnectLimit) {
      //print('tryReconnect: limit excedido');
      //return;
      throw PostgresqlException(
          'Connection is notConnected,reconnection limit exceeded, cannot execute query.',
          errorCode: 501);
    }

    _tryReconnectCount++;

    await connect();

    //print('tryReconnect fim: _connectionState ${_connectionState}');
  }

  /// processa a fila
  void _processSendQueryQueue() async {
   // print( 'CoreConnection@_processSendQueryQueue _connectionState: $_connectionState}');
    var queryQueue = _sendQueryQueue;
    if (_currentTransaction != null) {
    //  print('CoreConnection@_processSendQueryQueue in transaction');
      queryQueue = _currentTransaction!.sendQueryQueue;
    }

    if (queryQueue.isEmpty) {
     // print('CoreConnection@_processSendQueryQueue query queue empty');
      return;
    }
    if (_query != null) {
     // print('CoreConnection@_processSendQueryQueue _query != null');
      return;
    }
    if (_connectionState != ConnectionState.idle) {
     // print(  'CoreConnection@_processSendQueryQueue state != ConnectionState.idle');
      return;
    }

    //assert(_connectionState == ConnectionState.idle);
    _query = queryQueue.removeFirst();
    final query = _query!;
    query.state = QueryState.busy;

    if (query.queryType == QueryType.simple) {
      _sendExecuteSimpleStatement(query);
    } else if (query.queryType == QueryType.prepareStatement) {
      _sendPreparedStatement(query);
    } else if (query.queryType == QueryType.execStatement) {
      _sendExecuteStatement(query);
    }
    _connectionState = ConnectionState.busy;
    query.state = QueryState.busy;
    transactionState = TransactionState.unknown;
    //print('_processSendQueryQueue: ${query.sql}');
  }

  dynamic _sendExecuteSimpleStatement(Query query) {
  //  print('CoreConnection@_sendExecuteSimpleStatement start');
    _send_message(QUERY,
        [...typeConverter.charsetEncode(query.getSql, textCharset), NULL_BYTE]);
    this._sock_flush();
  }

  dynamic _sendPreparedStatement(Query query) {
    final statementNameBytes = [
      ...typeConverter.charsetEncode(query.statementName, defaultCodeCharset),
      NULL_BYTE
    ];
    _send_PARSE(statementNameBytes, query.getSql, query.oids);
    _send_DESCRIBE_STATEMENT(statementNameBytes);
    this._sock_write(SYNC_MSG);
    this._sock_flush();
  }

  Future<dynamic> _sendExecuteStatement(Query query) async {
    var params = typeConverter.makeParams(query.preparedParams);
    final statementNameBytes = [
      ...typeConverter.charsetEncode(query.statementName, defaultCodeCharset),
      NULL_BYTE
    ];
    this._send_BIND(statementNameBytes, params);
    this._send_EXECUTE();
    this._sock_write(SYNC_MSG);
    this._sock_flush();
  }

  Future<dynamic> _sock_flush() async {
    try {
      return await _socket?.flush();
    } catch (e) {
      throw PostgresqlException('_sock_flush network error $e',
          connectionName: connectionName);
    }
  }

  /// write data to Socket
  void _sock_write(List<int> data) {
    try {
      this._socket?.add(data);
    } catch (e, s) {
      throw PostgresqlException('_sock_write network error $e $s',
          connectionName: connectionName);
    }
  }

  void _sendStartupMessage() {
    // Int32 - Message length, including self.
    // Int32(196608) - Protocol version number.  Version 3.0.
    // Any number of key/value pairs, terminated by a zero byte:
    //   String - A parameter name (user, database, or options)
    //   String - Parameter value

    // val is array of bytes
    var val = [...i_pack(protocol)];
    for (var entry in _initParams.entries) {
      val.addAll([
        ...typeConverter.charsetEncode(
            entry.key, defaultCodeCharset), //.toList()
        NULL_BYTE,
        ...entry.value,
        NULL_BYTE
      ]);
    }
    val.add(0);

    this._sock_write(i_pack(Utils.len(val) + 4));
    this._sock_write(val);
    _sock_flush();
    _connectionState = ConnectionState.authenticating;
  }

  var _buffer = Buffer();
  int? _msgType;
  int? _msgLength;

  /// ler dados do Socket
  /// loop
  void _readData(List<int> data) {
    //print('CoreConnection@_readData');
    try {
      if (_connectionState == ConnectionState.closed) {
        return;
      }
      _buffer.append(data);

      // Handle resuming after storing message type and length.
      final msgType = _msgType;
      if (msgType != null) {
        final msgLength = _msgLength!;
        if (msgLength > _buffer.bytesAvailable)
          return; // Wait for entire message to be in buffer.

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
          throw new PostgresqlException('Lost message sync.',
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
    } catch (_) {
      _destroy();
      rethrow;
    }
  }

  bool _checkMessageLength(int msgType, int msgLength) {
    //print('CoreConnection@_checkMessageLength');

    if (_connectionState == ConnectionState.authenticating) {
      if (msgLength < 8) return false;
      if (msgType == AUTHENTICATION_REQUEST && msgLength > 2000) return false;
      if (msgType == ERROR_RESPONSE && msgLength > 30000) return false;
    } else {
      if (msgLength < 4) return false;

      // These are the only messages from the server which may exceed 30,000
      // bytes.
      if (msgLength > 30000 &&
          (msgType != NOTICE_RESPONSE &&
              msgType != ERROR_RESPONSE &&
              msgType != COPY_DATA &&
              msgType != ROW_DESCRIPTION &&
              msgType != DATA_ROW &&
              msgType != FUNCTION_CALL_RESPONSE &&
              msgType != NOTIFICATION_RESPONSE)) {
        return false;
      }
    }
    return true;
  }

  void _readMessage(int msgType, int length) {
    //print('CoreConnection@_readMessage');
    //assert(_buffer.bytesAvailable >= length);
    final messageBytes = _buffer.readBytes(length);
    switch (msgType) {
      case NOTICE_RESPONSE:
        _handle_NOTICE_RESPONSE(messageBytes);
        break;
      case AUTHENTICATION_REQUEST:
        _handle_AUTHENTICATION_REQUEST(messageBytes);
        break;
      case PARAMETER_STATUS:
        _handle_PARAMETER_STATUS(messageBytes);
        break;
      case BACKEND_KEY_DATA:
        _handle_BACKEND_KEY_DATA(messageBytes);
        break;
      case READY_FOR_QUERY:
        _handle_READY_FOR_QUERY(messageBytes);
        break;
      case ERROR_RESPONSE:
        _handle_ERROR_RESPONSE(messageBytes);
        break;
      case ROW_DESCRIPTION:
        _handle_ROW_DESCRIPTION(messageBytes);
        break;
      case DATA_ROW:
        _handle_DATA_ROW(messageBytes);
        break;
      case COMMAND_COMPLETE:
        _handle_COMMAND_COMPLETE(messageBytes);
        break;
      case PARSE_COMPLETE:
        _handle_PARSE_COMPLETE(messageBytes);
        break;
      case BIND_COMPLETE:
        _handle_BIND_COMPLETE(messageBytes);
        break;
      case PARAMETER_DESCRIPTION:
        _handle_PARAMETER_DESCRIPTION(messageBytes);
        break;
      case NOTIFICATION_RESPONSE:
        _handle_NOTIFICATION_RESPONSE(messageBytes);
        break;
    }
  }

  void _handle_PARSE_COMPLETE(List<int> data) {
    // Byte1('1') - Identifier.
    //Int32(4) - Message length, including self.
    // print('handle_PARSE_COMPLETE ${charsetDecode(data, allowMalformed: true)}');
  }

  void _handle_BIND_COMPLETE(List<int> data) {
    // print('handle_BIND_COMPLETE ${charsetDecode(data, allowMalformed: true)}');
    //informa que terminaou a execução dos passos de uma prepared query
    _query?.isPreparedComplete = true;
  }

  void _handle_PARAMETER_DESCRIPTION(List<int> data) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    // print(  'handle_PARAMETER_DESCRIPTION ${charsetDecode(data, allowMalformed: true)}');
    // count = h_unpack(data)[0]
    //context.parameter_oids = unpack_from("!" + "i" * count, data, 2)
  }

  void _handle_BACKEND_KEY_DATA(List<int> data) {
    backendPid = i_unpack(data).first;
    //print('handle_BACKEND_KEY_DATA _backendPid ${_backendPid}');
  }

  void _handle_READY_FOR_QUERY(List<int> data) {
   // print('CoreConnection@_handle_READY_FOR_QUERY');
    this._transaction_status = data;
    int c = c_unpack(data)[0];

    // const int IDLE = 73; //b"I"
    // const int IN_TRANSACTION = 84; //b"T"
    // const int IN_FAILED_TRANSACTION = 69; // b"E"

    if (c == IDLE || c == IN_TRANSACTION || c == IN_FAILED_TRANSACTION) {
      if (c == IDLE) {
        transactionState = TransactionState.none;
      } else if (c == IN_TRANSACTION) {
        transactionState = TransactionState.begun;
      } else if (c == IN_FAILED_TRANSACTION) {
        transactionState = TransactionState.error;
      }

      var was = _connectionState;
      _connectionState = ConnectionState.idle;

      if (was == ConnectionState.authenticated) {
        hasConnected = true;
        _connected.complete(this);
      }

      //print( 'handle_READY_FOR_QUERY ${_query?.queryType} | ${_query?.state} | ${_query?.error}');
      if (_query != null) {
        //print('_query != null');
        final query = _query!;
        if (query.error != null) {
          query.addStreamError(query.error!, query.stackTrace);
        }
        query.close();
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

  void _handle_ROW_DESCRIPTION(List<int> data) {
   // print('CoreConnection@_handle_ROW_DESCRIPTION start ');
    _connectionState = ConnectionState.streaming;
    var count = h_unpack(data)[0];
    var idx = 2;

    /// informações das colunas
    var list = <ColumnDescription>[];

    /// funções de converção de tipos
    //var input_funcs = <Function>[];

    for (var i = 0; i < count; i++) {
      var name = data.sublist(idx, data.indexOf(NULL_BYTE, idx));
      idx += Utils.len(name) + 1;
      var unpackValues = ihihih_unpack(data, idx);
      //var field = <String, dynamic>{};
      // field["table_oid"] = unpackValues[0];
      // field["column_attrnum"] = unpackValues[1];
      // field["type_oid"] = unpackValues[2];
      // field["type_size"] = unpackValues[3];
      // field["type_modifier"] = unpackValues[4];
      // field["format"] = unpackValues[5];
      // field['name'] = typeConverter.charsetDecode(name, textCharset);
      //columns.add(field);
      int tableOid = unpackValues[0]; //fieldId
      int columnAttrnum = unpackValues[1]; //tableColNo
      int typeOid = unpackValues[2]; //fieldType
      int typeSize = unpackValues[3]; //dataSize
      int typeModifier = unpackValues[4]; //typeModifier
      int formatCode = unpackValues[5]; //formatCode
      String fieldName = typeConverter.charsetDecode(name, textCharset);
      idx += 18;

      list.add(ColumnDescription(i, fieldName, tableOid, columnAttrnum, typeOid,
          typeSize, typeModifier, formatCode));
      //mapeias a funções de conversão de tipo para estas colunas
      //input_funcs.add(PG_TYPES[field["type_oid"]]);
    }

    final query = _query!;
    query.columnCount = count;
    query.columns = UnmodifiableListView(list);
    //query.commandIndex++;
    //query.input_funcs = input_funcs;
    //isso é por que prepareStatement não emite COMMAND_COMPLETE
    if (query.queryType == QueryType.prepareStatement) {
      query.state = QueryState.done;
    }
  }

  /// obtem as linhas de resultado do postgresql
  void _handle_DATA_ROW(List<int> data) {
    // print('handle_DATA_ROW');

    final query = _query!;

    var idx = 2;
    var row = [];
    var v;
    for (var i = 0; i < query.columnCount; i++) {
      var col = query.columns![i];
      var vlen = i_unpack(data, idx)[0];
      idx += 4;
      if (vlen == -1) {
        v = null;
      } else {
        var bytes = data.sublist(idx, idx + vlen);
        var stringVal = typeConverter.charsetDecode(bytes, textCharset);
        //v = func(stringVal); decodeValue
        v = typeConverter.decodeValuePg8000(
          stringVal,
          col.fieldType,
        );
        idx += vlen;
        //print('handle_DATA_ROW $stringVal | $v | ${v.runtimeType}');
      }
      row.add(v);
    }
    query.addRow(row);
  }

  void _handle_COMMAND_COMPLETE(List<int> data) {
    final query = _query;
    // transactionState == TransactionState.error
    if (_transaction_status?.first == IN_FAILED_TRANSACTION &&
        query?.error != null) {
      //
      //sql = context.statement.split()[0].rstrip(";").upper()
      //if (query.sql != "ROLLBACK") {
     // print('in failed transaction block');
      //}
    }

    var commandString = typeConverter.charsetDecode(
        data.sublist(0, data.length - 1), textCharset);
    var values = commandString.split(' ');
    int rowsAffected = int.tryParse(values.last) ?? 0;
    if (query != null) {
      query.state = QueryState.done;
      //query.commandIndex++;
      query.rowsAffected.value = rowsAffected;
      //print("handle_COMMAND_COMPLETE ${query.rowsAffected.value}");
    }
  }

  /// [statement_name_bin] name statement bytes
  void _send_PARSE(List<int> statement_name_bin, String statement, List? oids) {
    //bytearray
    var val = <int>[...statement_name_bin];
    val.addAll(
        [...typeConverter.charsetEncode(statement, textCharset), NULL_BYTE]);

    oids = oids != null ? oids : [];
    val.addAll(h_pack(Utils.len(oids)));
    for (var oid in oids) {
      val.addAll(i_pack(oid == -1 ? 0 : oid));
    }

    this._send_message(PARSE, val);
    this._sock_write(FLUSH_MSG);
  }

  /// [statement_name_bin] é uma lista de bytes
  void _send_DESCRIBE_STATEMENT(List<int> statement_name_bin) {
    this._send_message(DESCRIBE, [STATEMENT, ...statement_name_bin]);
    this._sock_write(FLUSH_MSG);
  }

  /// envia a mensagem BIND
  void _send_BIND(List<int> statement_name_bin, List params) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html

    var retval = <int>[
      NULL_BYTE,
      ...statement_name_bin,
      ...h_pack(0),
      ...h_pack(Utils.len(params))
    ];

    for (var value in params) {
      if (value == null) {
        retval.addAll(i_pack(-1));
      } else {
        var val = typeConverter.charsetEncode(value, textCharset);
        retval.addAll(i_pack(Utils.len(val)));
        retval.addAll(val);
      }
    }
    retval.addAll(h_pack(0));
    _send_message(BIND, retval);
    _sock_write(FLUSH_MSG);
  }

  /// envia a mensagem EXECUTE_MSG
  void _send_EXECUTE() {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    this._sock_write(EXECUTE_MSG);
    this._sock_write(FLUSH_MSG);
  }

  /// envia mensagem para o postgreSql
  /// ou seja grava uma mensgame no Socket
  void _send_message(int code, List<int> bytes) {
    //print('CoreConnection@_send_message start');
    try {
      this._sock_write([code]);
      this._sock_write(i_pack(Utils.len(bytes) + 4));
      this._sock_write(bytes);
    } catch (e) {
      throw PostgresqlException('_send_message connection is closed $e',
          connectionName: connectionName);
    }
  }

  void _handle_NOTICE_RESPONSE(List<int> data) {
    //print('CoreConnection@_handle_NOTICE_RESPONSE start');

    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    //this.notices.add({s[0:1]: s[1:] for s in data.split(NULL_BYTE)});
    var dataSplit = Utils.splitList(data, NULL_BYTE);
    final map = <String, String>{};
    for (var bytes in dataSplit) {
      if (bytes.isNotEmpty) {
        var key = typeConverter.charsetDecode(
            bytes.sublist(0, 1), defaultCodeCharset);
        map[key] = typeConverter.charsetDecode(bytes.sublist(1), textCharset);
      }
    }
    final msg = ServerNotice(false, map, connectionName);
    if (!_notices.isClosed) _notices.add(msg);
    //print('handle_NOTICE_RESPONSE $map');
  }

  void _handle_NOTIFICATION_RESPONSE(List<int> data) {
    //print('CoreConnection@_handle_NOTIFICATION_RESPONSE start');
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    //print('_handle_NOTIFICATION_RESPONSE');
    var backend_pid = i_unpack(data)[0];
    var idx = 4;
    var null_idx = data.indexOf(NULL_BYTE, idx);

    var channel =
        typeConverter.charsetDecode(data.sublist(idx, null_idx), textCharset);
    var payload = typeConverter.charsetDecode(
        data.sublist(null_idx + 1, data.length - 1), textCharset);
    this._notifications.add(
        {'backendPid': backend_pid, 'channel': channel, 'payload': payload});
  }

  void _handle_AUTHENTICATION_REQUEST(List<int> data) {
   // print('CoreConnection@_handle_AUTHENTICATION_REQUEST start');
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    //print('handle_AUTHENTICATION_REQUEST');

    if (_connectionState != ConnectionState.authenticating) {
      throw PostgresqlException(
          'Invalid connection state while authenticating.',
          connectionName: connectionName);
    }
    final authCode = i_unpack(data)[0];
    authenticationRequestType = AuthenticationRequestType.fromCode(authCode);

    if (authenticationRequestType == AuthenticationRequestType.Ok) {
      _connectionState = ConnectionState.authenticated;
      return;
    } else if (authenticationRequestType ==
        AuthenticationRequestType.CleartextPassword) {
      if (this.password == null)
        throw PostgresqlException(
            'server requesting cleartext password authentication, but no password was provided',
            connectionName: connectionName);
      this._send_message(PASSWORD, [...this.passwordBytes, NULL_BYTE]);
      this._sock_flush();
    }
    //md5 AUTHENTICATION
    else if (authenticationRequestType ==
        AuthenticationRequestType.MD5Password) {
      if (this.password == null) {
        throw PostgresqlException(
            'server requesting MD5 password authentication, but no password  was provided',
            connectionName: connectionName);
      }
      var salt = cccc_unpack(data, 4);
      //md5 message send to server
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

      this._send_message(PASSWORD, [...pwd, NULL_BYTE]);
      this._sock_flush();
    }
    // AuthenticationSASL
    else if (authenticationRequestType == AuthenticationRequestType.SASL) {
      //print('AuthenticationSASL $auth_code');

      var dataPart = data.sublist(4, data.length - 2);
      //var dataPartSplit = Utils.splitAround(data, (v) => v == NULL_BYTE, (v) => v != NULL_BYTE);
      var dataPartSplit = Utils.splitList(dataPart, NULL_BYTE);
      var mechanisms = dataPartSplit
          .map((e) => typeConverter.charsetDecode(e, defaultCodeCharset))
          .toList();

      this.scramAuthenticator = ScramAuthenticator(
        mechanisms.last,
        // 'SCRAM-SHA-256', // Optionally choose hash method from a list provided by the server
        sha256,
        UsernamePasswordCredential(
            username: this.user, password: this.password),
      );

      var init = this.scramAuthenticator!.handleMessage(
            // Get type type from the server message
            SaslMessageType.AuthenticationSASL,
            // Append the remaining bytes from serve if need
            Uint8List.fromList([]),
            specifyUsername: true,
          );

      var mech = [
        ...typeConverter.charsetEncode(
            this.scramAuthenticator!.mechanism.name, defaultCodeCharset),
        NULL_BYTE
      ];
      var saslInitialResponse = [...mech, ...i_pack(Utils.len(init)), ...init!];
      //  SASLInitialResponse
      this._send_message(PASSWORD, saslInitialResponse);
      this._sock_flush();
    } else if (authenticationRequestType ==
        AuthenticationRequestType.SASLContinue) {
      // AuthenticationSASLContinue

      var msg = this.scramAuthenticator!.handleMessage(
            SaslMessageType.AuthenticationSASLContinue,
            // Append the bytes receiver from server
            Uint8List.fromList(data.sublist(4)),
          );
      this._send_message(PASSWORD, msg!);
      this._sock_flush();
    } else if (authenticationRequestType ==
        AuthenticationRequestType.SASLFinal) {
      // AuthenticationSASLFinal

      this.scramAuthenticator!.handleMessage(
            SaslMessageType.AuthenticationSASLFinal,
            // Append the bytes receiver from server
            Uint8List.fromList(data.sublist(4)),
          );
      //2=KerberosV5, 4=CryptPassword, 6=SCMCredential, 7=GSS, 8=GSSContinue, 9=SSPI
    } else if ([2, 4, 6, 7, 8, 9].contains(authCode))
      throw PostgresqlException(
          'Authentication method $authCode not supported.',
          connectionName: connectionName);
    else {
      throw PostgresqlException(
          'Authentication method $authCode not recognized.',
          connectionName: connectionName);
    }
  }

  /// obtem as informações do servidor
  void _handle_PARAMETER_STATUS(List<int> data) {
    //print('CoreConnection@_handle_PARAMETER_STATUS start');

    var pos = data.indexOf(NULL_BYTE);
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
      } else {
        //print('_handle_PARAMETER_STATUS _notices.isClosed');
      }
    }

    switch (key.toLowerCase()) {
      case 'client_encoding':
        serverInfo.clientEncoding = value;
        // clientEncoding = typeConverter.PG_PY_ENCODINGS[value.trim().toLowerCase()];
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
        serverInfo.timeZone = value;
        break;
    }
  }

  void _handleSocketError(dynamic error, {bool closed = false}) {
   // print('CoreConnection@_handleSocketError start _connectionState: $_connectionState $hasConnected');

    if (_connectionState == ConnectionState.closed) {
      _notices.add(ClientNotice(
          isError: false,
          severity: 'WARNING',
          message: 'Socket error after socket closed.',
          connectionName: connectionName,
          exception: error));
      _destroy();
      return;
    }

    _destroy();
    var msg = closed ? 'Socket closed unexpectedly.' : 'Socket error.';

    if (hasConnected == false) {
      throw PostgresqlException(msg,
          errorCode: error, connectionName: connectionName);
      // _connected.completeError(PostgresqlException(msg,
      //     errorCode: error, connectionName: connectionName));
    } else {
      final query = _query;
      if (query != null) {
        query.state = QueryState.error;
        query.error = PostgresqlException(msg,
            errorCode: error,
            connectionName: connectionName,
            sql: query.getSql);
      } else {
        _notices.add(ClientNotice(
            isError: true,
            connectionName: connectionName,
            severity: 'ERROR',
            message: msg,
            exception: error));
      }
    }
  }

  void _handleSocketClosed() {
   // print('CoreConnection@_handleSocketClosed start _connectionState $_connectionState');

    if (_connectionState != ConnectionState.closed) {
      _handleSocketError(null, closed: true);
    }

    if (allowAttemptToReconnect == true) {
      //print('_handleSocketClosed allowAttemptToReconnect: $allowAttemptToReconnect');
      tryReconnect();
    }
  }

  void _handle_ERROR_RESPONSE(List<int> data) async {
    //print('CoreConnection@_handle_ERROR_RESPONSE start _connectionState $_connectionState');
    var dataSplit = Utils.splitList<int>(data, NULL_BYTE);

    // var mapKeyToVal = {
    //   RESPONSE_SEVERITY_S: 'severity_s',
    //   RESPONSE_SEVERITY: 'severity_v',
    //   RESPONSE_CODE: 'code',
    //   RESPONSE_MSG: 'msg',
    //   RESPONSE_DETAIL: 'detail',
    //   RESPONSE_HINT: 'hint',
    //   RESPONSE_POSITION: 'position',
    //   RESPONSE__POSITION: '_position',
    //   RESPONSE__QUERY: 'query',
    //   RESPONSE_WHERE: 'where',
    //   RESPONSE_FILE: 'file',
    //   RESPONSE_LINE: 'line',
    //   RESPONSE_ROUTINE: 'routine',
    // };

    var map = <String, String>{};
    for (var bytes in dataSplit) {
      if (bytes.isNotEmpty) {
        var key = typeConverter.charsetDecode(
            bytes.sublist(0, 1), defaultCodeCharset);
        // var keyM = mapKeyToVal[key];
        // if (keyM != null) {
        //   key = keyM;
        // }
        map[key] = typeConverter.charsetDecode(
            bytes.sublist(1), textCharset); //textCharset);
      }
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

    //print('handle_ERROR_RESPONSE $map \r\n hasConnected: $hasConnected');

    if (hasConnected == false) {
      _connectionState = ConnectionState.closed;
      this._socket?.destroy();
      _connected.completeError(postgresqlException);
    } else {
      final query = _query;

      query?.error = postgresqlException;
      query?.state = QueryState.error;
      query?.addStreamError(postgresqlException);
      query?.close();

      //if code is 57P01 postgresql restart
      if (msg.code?.startsWith('57P') ?? false) {
        //print( 'handle_ERROR_RESPONSE PG stop/restart query $query ${query?.getSql}');
        _query = null;
        _connectionState = ConnectionState.closed;
        _socket?.close();
        _socket?.destroy();

        //throw postgresqlException;

        //PG stop/restart
        // final ow = owner;
        // if (ow != null)
        //   ow.destroy();
        // else {
        //   _connectionState = ConnectionState.closed;
        //   _socket?.destroy();
        // }
      }
    }
  }

  Future<void> close() async {
    //print('CoreConnection@close start _connectionState = $_connectionState');
    if (_connectionState == ConnectionState.closed) return;

    _connectionState = ConnectionState.closed;
    hasConnected = false;
    // If a query is in progress then send an error and close the result stream.
    final query = _query;
    if (query != null) {
      var c = query;
      if (!c.streamIsClosed) {
        var postgresqlException = PostgresqlException(
            'Connection closed before query could complete ',
            connectionName: connectionName);
        c.state = QueryState.error;
        c.error = postgresqlException;
        c.addStreamError(postgresqlException);
        await c.close();
        _query = null;
      }
    }

    //
    try {
      _sock_write(TERMINATE_MSG);
     // print('CoreConnection@close send _MSG_TERMINATE');
      await _sock_flush();
      await _socket?.close();
    } catch (e, st) {
     // print('CoreConnection@close error');
      if (_notices.isClosed == false) {
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
      // await _socket.close();
      // _socket = null;
      _destroy();
      _connectionState = ConnectionState.closed;
    }
    // print('CoreConnection closed');
  }

  void _destroy() {
    //print('CoreConnection@_destroy start');
    hasConnected = false;
    _connectionState = ConnectionState.closed;
    this._socket?.destroy();
    Timer.run(_notices.close);
    Timer.run(_notifications.close);
  }
}

///A owner of [Connection].
abstract class ConnectionOwner {
  /// Destroys the connection.
  /// It is called if the connection is no longer available.
  /// For example, server restarts or crashes.
  void destroy();
}

/// See http://www.postgresql.org/docs/9.3/static/transaction-iso.html
class TransactionIsolation {
  final String value;
  const TransactionIsolation(this.value);

  @override
  String toString() => value;

  static const TransactionIsolation readCommitted =
      const TransactionIsolation('readCommitted');
  static const TransactionIsolation repeatableRead =
      const TransactionIsolation('repeatableRead');
  static const TransactionIsolation serializable =
      const TransactionIsolation('serializable');
}
