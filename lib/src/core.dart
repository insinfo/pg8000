// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pg8000/src/buffer_experiments/ReadBuffer.dart';
import 'package:pg8000/src/row_info.dart';
import 'package:pg8000/src/sasl_scram/sasl_scram.dart';
import 'package:pg8000/src/utils/utils.dart';

import 'client_notice.dart';
import 'column_description.dart';
import 'converters.dart';
import 'exceptions.dart';
import 'server_info.dart';
import 'server_notice.dart';
import 'ssl_context.dart';
import 'substitute.dart';
import 'transaction_context.dart';
import 'utils/buffer.dart';
import 'connection_state.dart';

import 'transaction_state.dart';

/// conversão Python to Dart
///        type Python          |  type dart
///  deque "Double-ended queue" |  Queue

/// https://docs.python.org/3/library/struct.html#format-characters
/// Format |    C Type   |   Python type     | Standard size
///   h    |    short    |    integer        |   2
///   i    |    int      |    integer        | 	4
///   c    |   char      | bytes of length 1 | 1
///   b    | signed char | integer           | 1
///   q    | long long   | integer           | 8
///   Q    | unsigned long long |  integer   |  8
///
/// pega valores não-byte (por exemplo, inteiros, strings, etc.)
/// e os converte em bytes usando o formato especificado
List<int> pack(String fmt, List<int> vals) {
  var formats = fmt.split('');

  if (vals.length != formats.length) {
    throw Exception(
        'pack expected ${formats.length} items for packing (got ${formats.length})');
  }
  var bytes = <int>[];

  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    var val = vals[i];
    if (f == 'c' || f == 'b') {
      assert(val >= 0 && val < 256);
      bytes.add(val);
    } //Int16 short 2 bytes
    else if (f == 'h') {
      assert(val >= -32768 && val <= 32767);
      if (val < 0) val = 0x10000 + val;

      int a = (val >> 8) & 0x00FF;
      int b = val & 0x00FF;
      //checar ordem
      bytes.add(a);
      bytes.add(b);
    } //Int32 int 4 bytes
    else if (f == 'i') {
      assert(val >= -2147483648 && val <= 2147483647);

      if (val < 0) val = 0x100000000 + val;

      int a = (val >> 24) & 0x000000FF;
      int b = (val >> 16) & 0x000000FF;
      int c = (val >> 8) & 0x000000FF;
      int d = val & 0x000000FF;
      //checar ordem

      bytes.add(a);
      bytes.add(b);
      bytes.add(c);
      bytes.add(d);
    } else {
      throw Exception('format unknow');
    }
  }

  return bytes;
}

List<int> unpack(String fmt, List<int> bytes, [int offset = 0]) {
  // var sizes = [
  //   {'i': 4},
  //   {'c': 1},
  //   {'h': 2},
  //   {'b': 1},
  //   {'q': 8},
  //   {'Q': 8}
  // ];

  var decodedNum = <int>[];
  var buffer = Buffer();

  if (offset == 0) {
    buffer.append(bytes);
  } else if (offset > 0) {
    var bits = bytes.sublist(offset);
    buffer.append(bits);
  } else {
    throw Exception('offset < 0');
  }

  var formats = fmt.split('');
  for (var i = 0; i < formats.length; i++) {
    var f = formats[i];
    if (f == 'c' || f == 'b') {
      decodedNum.add(buffer.readByte());
    } else if (f == 'i') {
      decodedNum.add(buffer.readInt32());
    } else if (f == 'h') {
      decodedNum.add(buffer.readInt16());
    } else {
      throw Exception('format unknow');
    }
  }
  return decodedNum;
}

/// write char 1 byte
List<int> c_pack(int val) {
  return pack('c', [val]);
}

/// readByte
List<int> c_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('c', bytes, offset);
}

/// pega valores não-byte (por exemplo, inteiros)
/// e os converte em bytes usando o formato "i" int de 4 bytes
List<int> i_pack(int val) {
  return pack('i', [val]);
}

/// readInt32
List<int> i_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('i', bytes, offset);
}

List<int> h_pack(int val) {
  return pack('h', [val]);
}

/// readInt16
List<int> h_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('h', bytes, offset);
}

List<int> ii_pack(int val1, int val2) {
  return pack('ii', [val1, val2]);
}

List<int> ii_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ii', bytes, offset);
}

List<int> ihihih_pack(int val1, int val2) {
  return pack('ihihih', [val1, val2]);
}

List<int> ihihih_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ihihih', bytes, offset);
}

List<int> ci_pack(int val1, int val2) {
  return pack('ci', [val1, val2]);
}

List<int> ci_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('ci', bytes, offset);
}

List<int> bh_pack(int val1, int val2) {
  return pack('bh', [val1, val2]);
}

List<int> bh_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('bh', bytes, offset);
}

List<int> cccc_pack(int val1, int val2, int val3, int val4) {
  return pack('cccc', [val1, val2, val3, val4]);
}

List<int> cccc_unpack(List<int> bytes, [int offset = 0]) {
  return unpack('cccc', bytes, offset);
}

const int NULL_BYTE = 0; // b"\x00"

// Message codes
const int NOTICE_RESPONSE = 78; //'N'.codeUnitAt(0) ;// b"N"
const int AUTHENTICATION_REQUEST = 82; // b"R"
const int PARAMETER_STATUS = 83; // b"S"
const int BACKEND_KEY_DATA = 75; // b"K"
const int READY_FOR_QUERY = 90; // b"Z"
const int ROW_DESCRIPTION = 84; // b"T"
const int ERROR_RESPONSE = 69; //b"E"
const int DATA_ROW = 68; // b"D"
const int COMMAND_COMPLETE = 67; // b"C"
const int PARSE_COMPLETE = 49; // b"1"
const int BIND_COMPLETE = 50; // b"2"
const int CLOSE_COMPLETE = 51; // b"3"
const int PORTAL_SUSPENDED = 115; //b"s"
const int NO_DATA = 98; //b"n"
const int PARAMETER_DESCRIPTION = 116; // b"t"
const int NOTIFICATION_RESPONSE = 65; //b"A"
const int COPY_DONE = 99; //b"c"
const int COPY_DATA = 100; //b"d"
const int COPY_IN_RESPONSE = 71; // b"G"
const int COPY_OUT_RESPONSE = 72; // b"H"
const int EMPTY_QUERY_RESPONSE = 73; // b"I"

String pgCodeString(int pgCode) {
  switch (pgCode) {
    case NOTICE_RESPONSE:
      return 'NOTICE_RESPONSE';
      break;
    case AUTHENTICATION_REQUEST:
      return 'AUTHENTICATION_REQUEST';
      break;

    case PARAMETER_STATUS:
      return 'PARAMETER_STATUS';
      break;
    case BACKEND_KEY_DATA:
      return 'BACKEND_KEY_DATA';
      break;
    case READY_FOR_QUERY:
      return 'READY_FOR_QUERY';
      break;
    case ROW_DESCRIPTION:
      return 'ROW_DESCRIPTION';
      break;
    case ERROR_RESPONSE:
      return 'ERROR_RESPONSE';
      break;
    case DATA_ROW:
      return 'DATA_ROW';
      break;
    case COMMAND_COMPLETE:
      return 'COMMAND_COMPLETE';
      break;
    case PARSE_COMPLETE:
      return 'PARSE_COMPLETE';
      break;
    case BIND_COMPLETE:
      return 'BIND_COMPLETE';
      break;
    case CLOSE_COMPLETE:
      return 'CLOSE_COMPLETE';
      break;
    case PORTAL_SUSPENDED:
      return 'PORTAL_SUSPENDED';
      break;
    case NO_DATA:
      return 'NO_DATA';
      break;
    case PARAMETER_DESCRIPTION:
      return 'PARAMETER_DESCRIPTION';
      break;
    case NOTIFICATION_RESPONSE:
      return 'NOTIFICATION_RESPONSE';
      break;
    case COPY_DONE:
      return 'COPY_DONE';
      break;
    case COPY_DATA:
      return 'COPY_DATA';
      break;
    case COPY_IN_RESPONSE:
      return 'COPY_IN_RESPONSE';
      break;
    case COPY_OUT_RESPONSE:
      return 'COPY_OUT_RESPONSE';
      break;
    case EMPTY_QUERY_RESPONSE:
      return 'EMPTY_QUERY_RESPONSE';
      break;
  }
  return 'unknow';
}

const int BIND = 66; //b"B"
const int PARSE = 80; // b"P"
const int QUERY = 81; // b"Q"
const int EXECUTE = 69; //b"E"
const int FLUSH = 72; //b"H"
const int SYNC = 83; // b"S"
const int PASSWORD = 112; //b"p"
const int DESCRIBE = 68; //b"D"
const int TERMINATE = 88; //b"X"
const int CLOSE = 67; // b"C"

List<int> _create_message(int code, [List<int> bytes = const <int>[]]) {
  return [code] + i_pack(bytes.length + 4) + bytes;
}

final FLUSH_MSG = _create_message(FLUSH); //'H\x00\x00\x00\x04'.codeUnits;
final SYNC_MSG = _create_message(SYNC);
final TERMINATE_MSG = _create_message(TERMINATE);
final COPY_DONE_MSG = _create_message(COPY_DONE);
final EXECUTE_MSG = _create_message(EXECUTE, [NULL_BYTE] + i_pack(0));

// DESCRIBE constants
const int STATEMENT = 83; // b"S"
const int PORTAL = 80; //b"P"

// ErrorResponse codes
const RESPONSE_SEVERITY_S = "S"; //83 always present
const RESPONSE_SEVERITY = "V"; //  86 // always present
const RESPONSE_CODE = "C"; // always present
const RESPONSE_MSG = "M"; // always present
const RESPONSE_DETAIL = "D";
const RESPONSE_HINT = "H";
const RESPONSE_POSITION = "P";
const RESPONSE__POSITION = "p";
const RESPONSE__QUERY = "q";
const RESPONSE_WHERE = "W";
const RESPONSE_FILE = "F";
const RESPONSE_LINE = "L";
const RESPONSE_ROUTINE = "R";

const int IDLE = 73; //b"I"
const int IN_TRANSACTION = 84; //b"T"
const int IN_FAILED_TRANSACTION = 69; // b"E"

class CoreConnection {
  List<int> userBytes;
  String host;
  String database;
  int port;
  List<int> passwordBytes;
  dynamic source_address;
  bool isUnixSocket = false;
  //SSLv3/TLS TLSv1.3
  SslContext sslContext;
  dynamic timeout;
  bool tcpKeepalive;
  String applicationName;
  dynamic replication;
  // for SCRAM-SHA-256 auth
  ScramAuthenticator scramAuthenticator;

  /// The owner of the connection, or null if not available.
  ConnectionOwner owner;

  String connectionName;
  int connectionId = 0;

  final _connected = Completer<CoreConnection>();

  // PreparedStatementState _preparedStatementState = PreparedStatementState.none;

  //bool autocommit = false;
  //dynamic _xid;
  //Set _statement_nums;

  Socket _socket;
  //client_encoding
  //String clientEncoding = 'utf8';

  String defaultCodeCharset = 'ascii'; //ascii
  String textCharset = 'utf8'; //utf8

  TypeConverter typeConverter;

  // var _commands_with_count = [
  //   "INSERT".codeUnits,
  //   "DELETE".codeUnits,
  //   "UPDATE".codeUnits,
  //   "MOVE".codeUnits,
  //   "FETCH".codeUnits,
  //   "COPY".codeUnits,
  //   "SELECT".codeUnits,
  // ];

  final _notifications = StreamController<dynamic>.broadcast();
  Stream<dynamic> get notifications => _notifications.stream;

  final _notices = StreamController<dynamic>.broadcast();
  Stream<dynamic> get notices => _notices.stream;

  //Map<String, dynamic> serverParameters = <String, dynamic>{};

  ServerInfo serverInfo = ServerInfo();

  String user;
  String password;

  Duration connectionTimeout = Duration(seconds: 180);

  //Future<dynamic> Function() _flush;
  //void Function(List<int> d) _write;

  ///  Int32(196608) - Protocol version number.  Version 3.0.
  int protocol = 196608;

  Map<String, dynamic> _initParams = <String, dynamic>{};

  List<int> _transaction_status;

  ConnectionState state = ConnectionState.notConnected;

  TransactionState transactionState = TransactionState.unknown;

  Buffer _buffer;
  // backend_key_data
  int backendPid = 0;

  bool hasConnected = false;
  // queue of queries to be executed
  final Queue<Query> _sendQueryQueue = Queue<Query>();
  Query _query;

  int _prepareStatementId = 0;
  //int _transactionLevel = 0;

  // transaction queue to be executed
  final _transactionQueue = Queue<TransactionContext>();
  TransactionContext _currentTransaction;
  int _transactionId = 0;

  /// [textCharset] utf8 | latin1 | ascii
  /// [host] ip, dns or unix socket
  CoreConnection(
    this.user, {
    this.host = 'localhost',
    this.database,
    this.port = 5432,
    this.password,
    this.source_address,
    this.isUnixSocket = false,
    this.sslContext,
    this.timeout,
    this.tcpKeepalive = true,
    this.applicationName,
    this.replication,
    this.connectionName,
    this.textCharset = 'utf8',
  }) {
    typeConverter =
        TypeConverter(textCharset, serverInfo, connectionName: connectionName);
    _init();
  }

  void _init() {
    if (user == null) {
      throw PostgresqlException(
          "The 'user' connection parameter cannot be null");
    }

    if (connectionName == null) {
      connectionName = 'pg8000_$connectionId';
    }
    connectionId++;

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

    _buffer = Buffer();

    this.userBytes = _initParams['user'];

    if (password is String) {
      this.passwordBytes = typeConverter.charsetEncode(password, textCharset);
    }
  }

  void _setKeepAlive() {
    RawSocketOption option;
    if (Platform.isAndroid || Platform.isLinux) {
      option =
          RawSocketOption.fromBool(LINUX_SOL_SOCKET, LINUX_SO_KEEPALIVE, true);
    } else {
      option = RawSocketOption.fromBool(
          WINDOWS_SOL_SOCKET, WINDOWS_SO_KEEPALIVE, true);
    }
    _socket.setRawOption(option);
  }

  Future<CoreConnection> connect() async {
    if (isUnixSocket == false && host != null) {
      try {
        // remover waitFor no futuro
        _socket = await Socket.connect(host, port).timeout(connectionTimeout);

        if (tcpKeepalive == true) {
          _setKeepAlive();
        }

        state = ConnectionState.socketConnected;
      } catch (e) {
        print('CoreConnection $e');
        throw PostgresqlException(
            """Can't create a connection to host $host and port $port 
                    (timeout is $timeout and source_address is $source_address).""");
      }
    } else if (isUnixSocket == true) {
      //throw UnimplementedError('unix_sock not implemented');
      _socket = await Socket.connect(
              InternetAddress(host, type: InternetAddressType.unix), port)
          .timeout(connectionTimeout);
    } else {
      throw PostgresqlException("one of host or unix_sock must be provided");
    }

    if (sslContext != null) {
      _socket = await _connectSsl();
    }

    this._socket.listen(_readData,
        onError: _handleSocketError, onDone: _handleSocketClosed);
    _sendStartupMessage();

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
          ));
        } else {
          SecurityContext();
          SecureSocket.secure(
            socket,
            context: sslContext.context,
            onBadCertificate: sslContext.onBadCertificate,
            keyLog: sslContext.keyLog,
            supportedProtocols: sslContext.supportedProtocols,
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

  ///
  /// execute sql query without prepared statement (executeSimple) if params is null
  /// otherwise execute prepared statement without name (executeUnnamed)
  ///
  /// Example: con.execute('select * from crud_teste.pessoas limit \$1',[2])
  ///
  Future<int> execute(String sql, [List params]) async {
    var query = Query(sql);
    query.state = QueryState.init;
    if (params != null && params.isNotEmpty) {
      query.queryType = QueryType.unnamedStatement;
      query.addPreparedParams(params, []);
    } else {
      query.queryType = QueryType.simple;
    }
    _enqueueQuery(query);
    await query.stream.isEmpty;
    return query.rowsAffected ?? 0;
  }

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  Stream<Row> executeSimple(String statement, [values]) {
    try {
      if (values != null)
        statement = substitute(statement, values, typeConverter.encodeValue);
      var query = Query(statement);
      query.state = QueryState.init;
      query.queryType = QueryType.simple;
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
    }
  }

  /// execute a prepared unnamed statement
  /// Example: com.executeUnnamed('select * from crud_teste.pessoas limit \$1', [1]);
  Stream<Row> executeUnnamed(String statement, List params,
      [List oids = const []]) {
    try {
      var query = Query(statement);
      query.state = QueryState.init;
      query.queryType = QueryType.unnamedStatement;
      query.addPreparedParams(params, oids);
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
    }
  }

  /// return Query prepares with statementName for execute with (executeNamed)
  Future<Query> prepareStatement(statement, [List oids = const []]) async {
    var query = Query(statement);
    query.state = QueryState.init;
    query.prepareStatementId = _prepareStatementId;
    //generate unique name for named prepared Statement
    query.statementName = "pg8000_statement_${query.prepareStatementId}";

    _prepareStatementId++;
    query.queryType = QueryType.prepareStatement;
    query.addOids(oids);

    _enqueueQuery(query);

    await query.stream.isEmpty;

    //cria uma copia
    var newQuery = query.clone();
    return newQuery;
  }

  Stream<Row> executeNamed(Query query) {
    try {
      //cria uma copia
      var newQuery = query.clone();
      newQuery.state = QueryState.init;
      print('execute_named ');
      newQuery.queryType = QueryType.namedStatement;

      //PreparedStatementState.executeStatement;
      _enqueueQuery(newQuery);
      return newQuery.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
    }
  }

  Future<TransactionContext> beginTransaction() async {
    var transaction = TransactionContext(_transactionId);
    //'START TRANSACTION'
    final commandBegin = 'begin';
    final stream = transaction.executeSimple(commandBegin);
    _enqueueTransaction(transaction);
    await stream.isEmpty;
    _transactionId++;
    return transaction;
  }

  Future<dynamic> rollBack(TransactionContext transaction) async {
    var stream = transaction.executeSimple('rollback');
    await stream.isEmpty;
    if (transaction == _currentTransaction) _currentTransaction = null;
  }

  Future<dynamic> commit(TransactionContext transaction) async {
    var stream = transaction.executeSimple('commit');
    await stream.isEmpty;
    if (transaction == _currentTransaction) _currentTransaction = null;
  }

  void _enqueueTransaction(TransactionContext transaction) {
    _transactionQueue.addLast(transaction);
    Timer.run(_processTransactionQueue);
  }

  void _processTransactionQueue() async {
    if (_transactionQueue.isEmpty) {
      print('_processTransactionQueue _transactionQueue.isEmpty');
      return;
    }
    if (_currentTransaction != null) {
      print('_processTransactionQueue _currentTransaction != null');
      return;
    }
    _currentTransaction = _transactionQueue.removeFirst();
    print('_processTransactionQueue $_currentTransaction');
    Timer.run(_processSendQueryQueue);
  }

  /// coloca a query na fila
  void _enqueueQuery(Query query) {
    if (query.sql == '') {
      throw PostgresqlException('SQL query is null or empty.');
    }

    if (query.sql.contains('\u0000')) {
      throw PostgresqlException('Sql query contains a null character.');
    }

    if (state == ConnectionState.closed) {
      throw PostgresqlException('Connection is closed, cannot execute query.');
    }
    query.state = QueryState.queued;
    _sendQueryQueue.addLast(query);
    Timer.run(_processSendQueryQueue);
  }

  /// processa a fila
  void _processSendQueryQueue() async {
    var queryQueue = _sendQueryQueue;
    if (_currentTransaction != null) {
      print('_processSendQueryQueue in transaction');
      queryQueue = _currentTransaction.sendQueryQueue;
    }

    if (queryQueue.isEmpty) {
      print('_processSendQueryQueue query queue empty');
      return;
    }
    if (_query != null) {
      print('_processSendQueryQueue _query != null');
      return;
    }
    if (state == ConnectionState.closed) {
      print('_processSendQueryQueue state == ConnectionState.closes');
      return;
    }
    assert(state == ConnectionState.idle);
    final query = _query = queryQueue.removeFirst();

    query.state = QueryState.busy;

    if (query.queryType == QueryType.simple) {
      _sendExecuteSimpleStatement(query);
    } else if (query.queryType == QueryType.unnamedStatement) {
      _sendExecuteUnnamedStatement(query);
    } else if (query.queryType == QueryType.prepareStatement) {
      await _sendPreparedStatement(query);
    } else if (query.queryType == QueryType.namedStatement) {
      await _sendExecuteNamedStatement(query);
    }
    state = ConnectionState.busy;
    query.state = QueryState.busy;
    transactionState = TransactionState.unknown;
  }

  Future<dynamic> _sendExecuteSimpleStatement(Query query) async {
    // execute_simple
    // print('send execute_simple ');
    _send_message(QUERY,
        [...typeConverter.charsetEncode(query.sql, textCharset), NULL_BYTE]);
    await this._sock_flush();
  }

  Future<dynamic> _sendExecuteUnnamedStatement(Query query) async {
    // execute_unnamed
    // print('send execute_unnamed');
    this._send_PARSE([NULL_BYTE], query.sql, query.oids);
    this._sock_write(SYNC_MSG);
    await this._sock_flush();
    // self.handle_messages(context);
    this._send_DESCRIBE_STATEMENT([NULL_BYTE]);
    this._sock_write(SYNC_MSG);
    await this._sock_flush();
    var params = typeConverter.makeParams(query.preparedParams);
    query.isPreparedComplete = false;
    this._send_BIND([NULL_BYTE], params);
    // this.handle_messages(context)
    this._send_EXECUTE();
    this._sock_write(SYNC_MSG);
    await this._sock_flush();
    // this.handle_messages(context)
  }

  Future<dynamic> _sendPreparedStatement(Query query) async {
    //print('send prepare_statement');
    var statementNameBytes = [
      ...typeConverter.charsetEncode(query.statementName, defaultCodeCharset),
      NULL_BYTE
    ];
    _send_PARSE(statementNameBytes, query.sql, query.oids);
    _send_DESCRIBE_STATEMENT(statementNameBytes);
    this._sock_write(SYNC_MSG);
    await this._sock_flush();
  }

  Future<dynamic> _sendExecuteNamedStatement(Query query) async {
    print('send namedStatement:');
    var params = typeConverter.makeParams(query.preparedParams);
    var statementNameBytes = [
      ...typeConverter.charsetEncode(query.statementName, defaultCodeCharset),
      NULL_BYTE
    ];
    this._send_BIND(statementNameBytes, params);
    this._send_EXECUTE();
    this._sock_write(SYNC_MSG);
    await this._sock_flush();
  }

  Future<dynamic> _sock_flush() {
    try {
      return this._socket.flush();
    } catch (e) {
      throw PostgresqlException("_sock_flush network error $e");
    }
  }

  /// grava dados no Socket
  void _sock_write(List<int> data) {
    try {
      return this._socket.add(data);
    } catch (e, s) {
      throw PostgresqlException("_sock_write network error $e $s");
    }
  }

  Future<void> _sendStartupMessage() async {
    //print('CoreConnection@_sendStartupMessage');
    // Int32 - Message length, including self.
    // Int32(196608) - Protocol version number.  Version 3.0.
    // Any number of key/value pairs, terminated by a zero byte:
    //   String - A parameter name (user, database, or options)
    //   String - Parameter value

    // val is array of bytes
    var val = i_pack(protocol);
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
    await _sock_flush();
    state = ConnectionState.authenticating;
  }

  /// ler dados do Socket
  /// loop
  void _readData(List<int> socketData) async {
    if (state == ConnectionState.closed) {
      return;
    }
    _buffer.append(socketData);

    while (state != ConnectionState.closed) {
      if (_buffer.bytesAvailable < 5) return; // Wait for more data.

      int msgType = _buffer.readByte();
      int length = _buffer.readInt32() - 4;

      print('_readData code: ${pgCodeString(msgType)} $msgType');
      var messageBytes = _buffer.readBytes(length);

      switch (msgType) {
        case NOTICE_RESPONSE:
          _handle_NOTICE_RESPONSE(messageBytes);
          break;
        case AUTHENTICATION_REQUEST:
          await _handle_AUTHENTICATION_REQUEST(messageBytes);
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
  }

  void _handle_PARSE_COMPLETE(List<int> data) {
    // Byte1('1') - Identifier.
    //Int32(4) - Message length, including self.
    // print('handle_PARSE_COMPLETE ${charsetDecode(data, allowMalformed: true)}');
  }

  void _handle_BIND_COMPLETE(List<int> data) {
    // print('handle_BIND_COMPLETE ${charsetDecode(data, allowMalformed: true)}');
    //informa que terminaou a execução dos passos de uma prepared query
    _query.isPreparedComplete = true;
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
    // print('handle_READY_FOR_QUERY');
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

      var was = state;
      state = ConnectionState.idle;

      if (was == ConnectionState.authenticated) {
        hasConnected = true;
        _connected.complete(this);
      }

      print('handle_READY_FOR_QUERY ${_query?.queryType} ${_query?.state}');

      //fix async call
      if (_query?.queryType == QueryType.prepareStatement) {
        _query?.close();
        _query = null;
      }
      if (_query?.state == QueryState.done) {
        _query?.close();
        _query = null;
      }

      Timer.run(_processSendQueryQueue);
    } else {
      _destroy();
      throw PostgresqlException(
        'Unknown ReadyForQuery transaction status: ${Utils.itoa(c)}.',
      );
    }
  }

  void _handle_ROW_DESCRIPTION(List<int> data) {
    //print('handle_ROW_DESCRIPTION ');
    state = ConnectionState.streaming;
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

    final query = _query;
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

    final query = _query;

    var idx = 2;
    var row = [];
    var v;
    for (var i = 0; i < query.columnCount; i++) {
      var col = query.columns[i];
      var vlen = i_unpack(data, idx)[0];
      idx += 4;
      if (vlen == -1) {
        v = null;
      } else {
        var bytes = data.sublist(idx, idx + vlen);
        var stringVal = typeConverter.charsetDecode(bytes, textCharset);
        //v = func(stringVal);
        v = typeConverter.decodeValue(
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
        query.error != null) {
      //sql = context.statement.split()[0].rstrip(";").upper()
      if (query.sql != "rollback") {
        print('in failed transaction block');
      }
    }

    var commandString = typeConverter.charsetDecode(
        data.sublist(0, data.length - 1), textCharset);
    var values = commandString.split(' ');
    int rowsAffected = int.tryParse(values.last) ?? 0;

    query.state = QueryState.done;
    //query.commandIndex++;
    query.rowsAffected = rowsAffected;

    print("handle_COMMAND_COMPLETE _query done");
  }

  /// [statement_name_bin] name statement bytes
  void _send_PARSE(List<int> statement_name_bin, String statement, List oids) {
    //bytearray
    var val = <int>[...statement_name_bin];
    val.addAll(
        [...typeConverter.charsetEncode(statement, textCharset), NULL_BYTE]);

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
    try {
      this._sock_write([code]);
      this._sock_write(i_pack(Utils.len(bytes) + 4));
      this._sock_write(bytes);
    } catch (e) {
      throw PostgresqlException("_send_message connection is closed $e");
    }
  }

  void _handle_NOTICE_RESPONSE(List<int> data) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    //this.notices.add({s[0:1]: s[1:] for s in data.split(NULL_BYTE)});
    var dataSplit = Utils.splitList(data, NULL_BYTE);
    var map = <String, String>{};
    for (var bytes in dataSplit) {
      if (bytes.isNotEmpty) {
        var key = typeConverter.charsetDecode(
            bytes.sublist(0, 1), defaultCodeCharset);
        map[key] = typeConverter.charsetDecode(bytes.sublist(1), textCharset);
      }
    }
    var msg = ServerNotice(false, map, connectionName);
    _notices.add(msg);
    print('handle_NOTICE_RESPONSE');
  }

  void _handle_NOTIFICATION_RESPONSE(List<int> data) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    print('_handle_NOTIFICATION_RESPONSE');
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

  Future<void> _handle_AUTHENTICATION_REQUEST(List<int> data) async {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    //print('handle_AUTHENTICATION_REQUEST');

    if (state != ConnectionState.authenticating) {
      throw PostgresqlException(
        'Invalid connection state while authenticating.',
      );
    }

    var auth_code = i_unpack(data)[0];
    //print('auth_code: $auth_code');
    if (auth_code == 0) {
      state = ConnectionState.authenticated;
      return;
    } else if (auth_code == 3) {
      if (this.password == null)
        throw PostgresqlException(
            "server requesting password authentication, but no password was provided");
      this._send_message(PASSWORD, [...this.passwordBytes, NULL_BYTE]);
      await this._sock_flush();
    }
    //md5 AUTHENTICATION
    else if (auth_code == 5) {
      if (this.password == null) {
        throw PostgresqlException(
            "server requesting MD5 password authentication, but no password  was provided");
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
      await this._sock_flush();
    }
    // AuthenticationSASL
    else if (auth_code == 10) {
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

      var init = this.scramAuthenticator.handleMessage(
            // Get type type from the server message
            SaslMessageType.AuthenticationSASL,
            // Append the remaining bytes from serve if need
            Uint8List.fromList([]),
            specifyUsername: true,
          );

      var mech = [
        ...typeConverter.charsetEncode(
            this.scramAuthenticator.mechanism.name, defaultCodeCharset),
        NULL_BYTE
      ];
      var saslInitialResponse = [...mech, ...i_pack(Utils.len(init)), ...init];
      //  SASLInitialResponse
      this._send_message(PASSWORD, saslInitialResponse);
      this._sock_flush();
    } else if (auth_code == 11) {
      // AuthenticationSASLContinue

      var msg = this.scramAuthenticator.handleMessage(
            SaslMessageType.AuthenticationSASLContinue,
            // Append the bytes receiver from server
            Uint8List.fromList(data.sublist(4)),
          );
      this._send_message(PASSWORD, msg);
      this._sock_flush();
    } else if (auth_code == 12) {
      // AuthenticationSASLFinal

      this.scramAuthenticator.handleMessage(
            SaslMessageType.AuthenticationSASLFinal,
            // Append the bytes receiver from server
            Uint8List.fromList(data.sublist(4)),
          );
    } else if ([2, 4, 6, 7, 8, 9].contains(auth_code))
      throw PostgresqlException(
          "Authentication method $auth_code not supported by pg8000.");
    else {
      throw PostgresqlException(
          "Authentication method $auth_code not recognized by pg8000.");
    }
  }

  /// obtem as informações do servidor
  void _handle_PARAMETER_STATUS(List<int> data) {
    //print('handle_PARAMETER_STATUS');
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
      _notices.add(ClientNotice(
          severity: 'WARNING', message: msg, connectionName: connectionName));
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
    print('_handleSocketError $error');

    if (state == ConnectionState.closed) {
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

    if (!hasConnected) {
      _connected.completeError(PostgresqlException(msg, errorCode: error));
    } else {
      final query = _query;
      if (query != null) {
        query.state = QueryState.done;
        query.addError(PostgresqlException(msg, errorCode: error));
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
    print('_handleSocketClosed');
    if (state != ConnectionState.closed) {
      _handleSocketError(null, closed: true);
    }
  }

  void _handle_ERROR_RESPONSE(List<int> data) {
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
        map[key] = typeConverter.charsetDecode(bytes.sublist(1), textCharset);
      }
    }

    var msg = ServerNotice(true, map, connectionName);

    var ex = PostgresqlException(
      msg.message,
      connectionName: connectionName,
      serverMessage: msg,
      errorCode: msg.code,
    );

    print('handle_ERROR_RESPONSE $map ');

    if (!hasConnected) {
      state = ConnectionState.closed;
      this._socket.destroy();
      _connected.completeError(ex);
    } else {
      final query = _query;
      if (query != null) {
        query.state = QueryState.done;
        query.addError(ex);
      } else {
        _notices.add(msg);
      }
      //if code is 57P01 postgresql restart
      if (msg.code?.startsWith('57P') ?? false) {
        //PG stop/restart
        final ow = owner;
        if (ow != null)
          ow.destroy();
        else {
          state = ConnectionState.closed;
          _socket.destroy();
        }
      }
    }
  }

  Future<void> close() async {
    if (state == ConnectionState.closed) return;

    state = ConnectionState.closed;

    // If a query is in progress then send an error and close the result stream.
    final query = _query;
    if (query != null) {
      var c = query._controller;
      if (!c.isClosed) {
        c.addError(PostgresqlException(
            'Connection closed before query could complete',
            connectionName: connectionName));
        await c.close();
        _query = null;
      }
    }

    if (_socket == null) {
      throw PostgresqlException("connection is closed");
    }

    //send _MSG_TERMINATE
    try {
      _sock_write(TERMINATE_MSG);
      await _sock_flush();
    } catch (e, st) {
      _notices.add(ClientNotice(
          severity: 'WARNING',
          message: 'Exception while closing connection. Closed without sending '
              'terminate message.',
          connectionName: connectionName,
          exception: e,
          stackTrace: st));
    } finally {
      // await _socket.close();
      // _socket = null;
      _destroy();
    }
    print('CoreConnection closed');
  }

  void _destroy() {
    state = ConnectionState.closed;
    this._socket.destroy();
    Timer.run(_notices.close);
    Timer.run(_notifications.close);
  }
}

class QueryState {
  final int value;
  const QueryState(this.value);
  static const QueryState queued = const QueryState(1);
  static const QueryState busy = const QueryState(6);
  static const QueryState streaming = const QueryState(7);
  static const QueryState done = const QueryState(8);
  static const QueryState init = const QueryState(9);

  @override
  String toString() {
    var v = '';
    if (value == 1) v = 'queued';
    if (value == 6) v = 'busy';
    if (value == 7) v = 'streaming';
    if (value == 8) v = 'done';
    if (value == 9) v = 'init';
    return 'QueryState.$v';
  }
}

class QueryType {
  final String value;
  const QueryType(this.value);
  static const QueryType prepareStatement = const QueryType('prepareStatement');
  static const QueryType unnamedStatement = const QueryType('unnamedStatement');
  static const QueryType namedStatement = const QueryType('namedStatement');
  static const QueryType simple = const QueryType('simple');

  @override
  String toString() {
    return 'QueryType.$value';
  }
}

class Query {
  //statement sql string
  final String sql;

  /// for prepared named statement
  String statementName;
  int prepareStatementId = 0;

  QueryState state = QueryState.queued;

  int rowsAffected = 0;

  /// params for prepared querys
  List _params;

  /// oids for prepared querys
  List _oids;

  /// se ouver params é uma Prepared query
  //bool get isPrepared => _params != null || _params?.isEmpty == true;

  QueryType queryType = QueryType.simple;

  /// informa que terminaou a execução dos passos de uma prepared query
  bool isPreparedComplete = false;

  List get preparedParams => _params;
  List get oids => _oids;

  /// funções de conversão de tipo para as colunas
  //List<Function> input_funcs = [];
  //List<List> _rows;
  int rowCount = -1;
  int columnCount = 0;

  /// informações das colunas
  List<ColumnDescription> columns;
  dynamic error = null;

  StreamController<Row> _controller = StreamController<Row>();
  Stream<Row> get stream => _controller.stream;

  void reInitStream() {
    _controller = StreamController<dynamic>();
  }

  Query(
    this.sql, {
    List preparedParamsP,
    this.prepareStatementId = 0,
    List oidsP,
    this.columns,
    //this.input_funcs = const [],
  }) {
    if (preparedParamsP != null) {
      _params = preparedParamsP;
    }

    if (oidsP != null) {
      _oids = oidsP;
    }

    error = null;
  }

  Query clone() {
    var newQuery = new Query(
      this.sql,
      columns: this.columns,
      prepareStatementId: this.prepareStatementId,
      preparedParamsP: this.preparedParams,
      oidsP: this.oids,
      //input_funcs: this.input_funcs,
    );
    newQuery.queryType = this.queryType;
    newQuery.columnCount = this.columnCount;
    newQuery.rowCount = this.rowCount;
    newQuery.rowsAffected = this.rowsAffected;
    newQuery.statementName = this.statementName;
    newQuery.error = this.error;
    newQuery.isPreparedComplete = this.isPreparedComplete;
    newQuery.state = this.state;

    return newQuery;
  }

  void addPreparedParams(List params, [List oids]) {
    _params = params;
    _oids = oids;
    isPreparedComplete = false;
  }

  void addOids(List oids) {
    _oids = oids;
  }

  void addRow(List<dynamic> rowData) {
    var row = Row(rowData, columns);
    rowCount++;
    //_rows.add(row);
    _controller.add(row);
  }

  Future<void> close() async {
    await _controller.close();
    state = QueryState.done;
    //print('Query@close');
  }

  void addError(Object err) {
    error = err;
    _controller.addError(err);
    // stream will be closed once the ready for query message is received.
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
