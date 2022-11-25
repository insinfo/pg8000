// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:pg8000/src/utils/utils.dart';

import 'converters.dart';
import 'exceptions.dart';
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
    case NOTICE_RESPONSE:
      return 'NOTICE_RESPONSE';
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
//const  RESPONSE_SEVERITY = "S";  //83 always present
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
  dynamic unix_sock;
  dynamic ssl_context;
  dynamic timeout;
  bool tcp_keepalive;
  String application_name;
  dynamic replication;

  /// The owner of the connection, or null if not available.
  ConnectionOwner owner;

  final _connected = Completer<CoreConnection>();

  Completer<Query> _preparedStatementCompleter;

  PreparedStatementState _preparedStatementState = PreparedStatementState.none;

  bool autocommit = false;
  dynamic _xid;
  Set _statement_nums;
  Map _caches = {};

  Socket _usock;

  String _client_encoding = "utf8";

  var _commands_with_count = [
    "INSERT".codeUnits,
    "DELETE".codeUnits,
    "UPDATE".codeUnits,
    "MOVE".codeUnits,
    "FETCH".codeUnits,
    "COPY".codeUnits,
    "SELECT".codeUnits,
  ];
  //maxlen=100
  Queue notifications = Queue();
  Queue notices = Queue();
  Map<String, dynamic> parameter_statuses = <String, dynamic>{};

  String user;
  String password;

  Duration connectionTimeout = Duration(seconds: 180);

  dynamic channel_binding;

  //Future<dynamic> Function() _flush;
  //void Function(List<int> d) _write;

  ///  Int32(196608) - Protocol version number.  Version 3.0.
  int protocol = 196608;

  Map<String, dynamic> init_params = <String, dynamic>{};

  List<int> _transaction_status;

  ConnectionState state = ConnectionState.notConnected;

  TransactionState transactionState = TransactionState.unknown;

  Buffer _buffer;

  int backendPid = 0;
  List<int> _backend_key_data;

  bool hasConnected = false;
  // fila de querys a serem executadas
  final Queue<Query> _sendQueryQueue = Queue<Query>();
  Query _query;

  CoreConnection(
    this.user, {
    this.host = "localhost",
    this.database,
    this.port = 5432,
    this.password,
    this.source_address,
    this.unix_sock,
    this.ssl_context,
    this.timeout,
    this.tcp_keepalive = true,
    this.application_name,
    this.replication,
  }) {
    _init();
  }

  void _init() {
    if (user == null) {
      throw PostgresqlException(
          "The 'user' connection parameter cannot be null");
    }

    init_params = <String, dynamic>{
      "user": user,
      "database": database,
      "application_name": application_name,
      "replication": replication,
    };

    var init_params_entries = [...init_params.entries];
    for (var entry in init_params_entries) {
      if (entry.value is String) {
        init_params[entry.key] = utf8.encode(entry.value);
      } else if (entry.value == null) {
        init_params.remove(entry.key);
      }
    }

    this.notifications = Queue();
    this.notices = Queue();

    _buffer = Buffer();

    this.userBytes = init_params["user"];

    if (password is String) {
      this.passwordBytes = utf8.encode(password);
    }

    this.autocommit = false;
    this._xid = null;
    this._statement_nums = Set();
    this._caches = {};

    //this._flush = _sock_flush;
    //this._write = _sock_write;
  }

  Future<CoreConnection> connect() async {
    if (unix_sock == null && host != null) {
      try {
        // remover waitFor no futuro
        _usock = await Socket.connect(host, port, timeout: connectionTimeout);
        //  .timeout(connectionTimeout, onTimeout: onTimeout);

        if (tcp_keepalive) {
          RawSocketOption option;
          if (Platform.isAndroid || Platform.isLinux) {
            option = RawSocketOption.fromBool(
                LINUX_SOL_SOCKET, LINUX_SO_KEEPALIVE, true);
          } else {
            option = RawSocketOption.fromBool(
                WINDOWS_SOL_SOCKET, WINDOWS_SO_KEEPALIVE, true);
          }
          _usock.setRawOption(option);
        }

        state = ConnectionState.socketConnected;
      } catch (e) {
        print('CoreConnection $e');
        throw PostgresqlException(
            """Can't create a connection to host $host and port $port 
                    (timeout is $timeout and source_address is $source_address).""");
      }
    } else if (unix_sock != null) {
      throw UnimplementedError('unix_sock not implemented');
    } else {
      throw PostgresqlException("one of host or unix_sock must be provided");
    }

    if (ssl_context != null) {
      throw UnimplementedError('ssl_context not implemented');
    }

    this._usock.listen(_readData,
        onError: _handleSocketError, onDone: _handleSocketClosed);
    _sendStartupMessage();

    return _connected.future;
  }

  /// execute a simple query whitout prepared statement
  Stream<dynamic> execute_simple(String statement) {
    try {
      //if (values != null) sql = substitute(sql, values, _typeConverter.encode);
      var query = Query(statement);
      query.queryType = QueryType.simple;
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
    }
  }

  /// execute a prepared unnamed statement
  /// Example: com.execute_unnamed('select * from crud_teste.pessoas limit \$1', [1]);
  Stream<dynamic> execute_unnamed(statement, List params,
      [List oids = const []]) {
    try {
      var query = Query(statement);
      query.queryType = QueryType.unnamedStatement;
      query.addPreparedParams(params, oids);
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
    }
  }

  /// return statement_name bytes
  Future<Query> prepare_statement(statement, [List oids = const []]) async {
    _preparedStatementCompleter = Completer<Query>();

    var query = Query(statement);
    query.queryType = QueryType.prepareStatement;
    query.addOids(oids);
    _preparedStatementState = PreparedStatementState.preparedStatement;
    _enqueueQuery(query);
    return _preparedStatementCompleter.future;
  }

  Stream<dynamic> execute_named(Query query) {
    try {
      query.queryType = QueryType.namedStatement;
      //query.reInitStream();
      _preparedStatementState = PreparedStatementState.executeStatement;
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
    }
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

    _sendQueryQueue.addLast(query);
    Timer.run(_processSendQueryQueue);
  }

  void _processSendQueryQueue() async {
    //print('_processSendQueryQueue a');
    if (_sendQueryQueue.isEmpty) {
      //print('_processSendQueryQueue _sendQueryQueue.isEmpty');
      return;
    }
    // if (_query != null) {
    //   print('_processSendQueryQueue _query != null');
    //   return;
    // }
    if (state == ConnectionState.closed) {
      print('_processSendQueryQueue state == ConnectionState.closes');
      return;
    }
    assert(state == ConnectionState.idle);
    final query = _query = _sendQueryQueue.removeFirst();
    //if vals

    if (query.queryType == QueryType.simple) {
      // execute_simple
      print('send execute_simple ');
      this._send_message(QUERY, [...utf8.encode(query.sql), NULL_BYTE]);
    } else if (query.queryType == QueryType.unnamedStatement) {
      // execute_unnamed
      print('send execute_unnamed');
      this._send_PARSE([NULL_BYTE], query.sql, query.oids);
      this._sock_write(SYNC_MSG);
      await this._sock_flush();
      // self.handle_messages(context);
      this._send_DESCRIBE_STATEMENT([NULL_BYTE]);
      this._sock_write(SYNC_MSG);

      await this._sock_flush();

      var params = make_params(PY_TYPES, query.preparedParams);
      query.isPreparedComplete = false;
      this._send_BIND([NULL_BYTE], params);
      // this.handle_messages(context)
      this._send_EXECUTE();

      this._sock_write(SYNC_MSG);
      await this._sock_flush();
      // this.handle_messages(context)
    } else if (query.queryType == QueryType.prepareStatement) {
      var statement_name_bin = <int>[];
      for (var i in Utils.sequence()) {
        var statement_name = "pg8000_statement_$i";
        statement_name_bin = [...ascii.encode(statement_name), NULL_BYTE];
        if (!_statement_nums.contains(statement_name_bin)) {
          _statement_nums.add(statement_name_bin);
          break;
        }
      }
      print('send prepare_statement');
      _send_PARSE(statement_name_bin, query.sql, query.oids);
      _send_DESCRIBE_STATEMENT(statement_name_bin);
      this._sock_write(SYNC_MSG);
      await this._sock_flush();
      query.statement_name_bin = statement_name_bin;
    } else if (query.queryType == QueryType.namedStatement) {
      print('send namedStatement:');
      var params = make_params(PY_TYPES, query.preparedParams);
      this._send_BIND(query.statement_name_bin, params);
      this._send_EXECUTE();
      this._sock_write(SYNC_MSG);
      await this._sock_flush();
    }
    state = ConnectionState.busy;
    query.state = QueryState.busy;
    transactionState = TransactionState.unknown;
  }

  Future<dynamic> _sock_flush() {
    try {
      return this._usock.flush();
    } catch (e) {
      throw PostgresqlException("_sock_flush network error $e");
    }
  }

  /// grava dados no Socket
  void _sock_write(List<int> data) {
    try {
      return this._usock.add(data);
    } catch (e, s) {
      throw Exception("_sock_write network error $e $s");
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
    for (var entry in init_params.entries) {
      val.addAll([
        ...ascii.encode(entry.key), //.toList()
        NULL_BYTE,
        ...entry.value,
        NULL_BYTE
      ]);
    }
    val.add(0);
    //print(utf8.decode(val));
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
    //print('_readData: $socketData');
    //print('_readData: ${utf8.decode(socketData, allowMalformed: true)}');

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
      }
    }
  }

  void _handle_PARSE_COMPLETE(List<int> data) {
    // Byte1('1') - Identifier.
    //Int32(4) - Message length, including self.
    // print('handle_PARSE_COMPLETE ${utf8.decode(data, allowMalformed: true)}');
  }

  void _handle_BIND_COMPLETE(List<int> data) {
    // print('handle_BIND_COMPLETE ${utf8.decode(data, allowMalformed: true)}');
    //informa que terminaou a execução dos passos de uma prepared query
    _query.isPreparedComplete = true;
  }

  void _handle_PARAMETER_DESCRIPTION(List<int> data) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    // print(  'handle_PARAMETER_DESCRIPTION ${utf8.decode(data, allowMalformed: true)}');
    // count = h_unpack(data)[0]
    //context.parameter_oids = unpack_from("!" + "i" * count, data, 2)
  }

  void _handle_BACKEND_KEY_DATA(List<int> data) {
    this._backend_key_data = data;
    backendPid = i_unpack(data).first;
    //print('handle_BACKEND_KEY_DATA _backendPid ${_backendPid}');
  }

  void _handle_READY_FOR_QUERY(List<int> data) {
    //print('handle_READY_FOR_QUERY ${data}');
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
      // if (_query?.isPrepared == false && _query?.isPreparedComplete == true) {
      //   print('handle_READY_FOR_QUERY _query = null;');
      //   _query?.close();
      //   _query = null;
      // }

      if (was == ConnectionState.authenticated) {
        hasConnected = true;
        _connected.complete(this);
      }
      if (_preparedStatementState == PreparedStatementState.preparedStatement) {
        _preparedStatementCompleter.complete(_query);
        _query.state == QueryState.done;
        print('_handle_READY_FOR_QUERY preparedStatement end $_query');
      }
      if (_query != null) {
        if (_query.state == QueryState.done) {
          _query?.close();
          _query = null;
          print('_handle_READY_FOR_QUERY _query close');
        }
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
    List<Map<String, dynamic>> columns = [];

    /// funções de converção de tipos
    var input_funcs = <Function>[];

    for (var i = 0; i < count; i++) {
      var name = data.sublist(idx, data.indexOf(NULL_BYTE, idx));
      idx += Utils.len(name) + 1;
      var unpackValues = ihihih_unpack(data, idx);
      var field = <String, dynamic>{};
      field["table_oid"] = unpackValues[0];
      field["column_attrnum"] = unpackValues[1];
      field["type_oid"] = unpackValues[2];
      field["type_size"] = unpackValues[3];
      field["type_modifier"] = unpackValues[4];
      field["format"] = unpackValues[5];
      field['name'] = utf8.decode(name);
      idx += 18;
      columns.add(field);
      //mapeias a funções de conversão de tipo para estas colunas
      input_funcs.add(PG_TYPES[field["type_oid"]]);
    }

    final query = _query;
    query.columnCount = count;
    query.columns = UnmodifiableListView(columns);
    query.commandIndex++;

    query.input_funcs = input_funcs;
  }

  /// obtem as linhas de resultado do postgresql
  void _handle_DATA_ROW(List<int> data) {
    // print('handle_DATA_ROW');

    final query = _query;

    var idx = 2;
    var row = [];
    var v;
    for (var func in query.input_funcs) {
      var vlen = i_unpack(data, idx)[0];
      idx += 4;
      if (vlen == -1) {
        v = null;
      } else {
        var bytes = data.sublist(idx, idx + vlen);
        var stringVal = utf8.decode(bytes);
        v = func(stringVal);
        idx += vlen;
        //print('handle_DATA_ROW $stringVal | $v | ${v.runtimeType}');
      }
      row.add(v);
    }
    query.addRow(row);
  }

  void _handle_COMMAND_COMPLETE(List<int> data) {
    var commandString = utf8.decode(data.sublist(0, data.length - 1));
    var values = commandString.split(' ');
    int rowsAffected = int.tryParse(values.last) ?? 0;

    //

    final query = _query;
    query.commandIndex++;
    query.rowsAffected = rowsAffected;

    // query.close();
    // _query = null;

    if (_query != null) {
      _query.state = QueryState.done;
      print("handle_COMMAND_COMPLETE _query done");
    }
  }

  /// [statement_name_bin] name statement bytes
  void _send_PARSE(List<int> statement_name_bin, String statement, List oids) {
    //bytearray
    var val = <int>[...statement_name_bin];
    val.addAll([...utf8.encode(statement), NULL_BYTE]);

    val.addAll(h_pack(Utils.len(oids)));
    for (var oid in oids) {
      val.addAll(i_pack(oid == -1 ? 0 : oid));
    }
    //print("send_PARSE val: ${utf8.decode(val)}");
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
        var val = utf8.encode(value);
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
    print('handle_NOTICE_RESPONSE');
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
    } else if (auth_code == 5) {
      if (this.password == null) {
        throw PostgresqlException(
            "server requesting MD5 password authentication, but no password  was provided");
      }
      // var passAndUserMd5 = ascii
      //     .encode(hex.encode(md5.convert([...passwordBytes, ...user]).bytes));
      // var pwd = [
      //   ..."md5".codeUnits,
      //   ...md5.convert([...passAndUserMd5, ...salt]).bytes,
      // ];
      var salt = cccc_unpack(data, 4);
      //md5 message to send to server
      var pwd = [
        ...'md5'.codeUnits,
        ...Utils.md5HexBytesAscii([
          ...Utils.md5HexBytesAscii([...passwordBytes, ...userBytes]),
          ...salt
        ])
      ];

      this._send_message(PASSWORD, [...pwd, NULL_BYTE]);
      await this._sock_flush();
    } else if (auth_code == 10) {
      // AuthenticationSASL
      //var mechanisms = [m.decode("ascii") for m in data[4:-2].split(NULL_BYTE)];

      // self.auth = scramp.ScramClient(
      //     mechanisms,
      //     self.user.decode("utf8"),
      //     self.password.decode("utf8"),
      //     channel_binding=self.channel_binding,
      // )

      // init = self.auth.get_client_first().encode("utf8")
      // mech = self.auth.mechanism_name.encode("ascii") + NULL_BYTE

      // # SASLInitialResponse
      // self._send_message(PASSWORD, mech + i_pack(len(init)) + init)
      // self._flush()
    } else if (auth_code == 11) {
      // AuthenticationSASLContinue
      // self.auth.set_server_first(data[4:].decode("utf8"))

      // // SASLResponse
      // msg = self.auth.get_client_final().encode("utf8")
      // self._send_message(PASSWORD, msg)
      // self._flush()
    } else if (auth_code == 12) {
      // AuthenticationSASLFinal
      //this.auth.set_server_final(data[4:].decode("utf8"))
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
    var key = ascii.decode(data.sublist(0, pos));
    var value = ascii.decode(data.sublist(pos + 1));
    parameter_statuses[key] = value;

    if (key == 'client_encoding') {
      _client_encoding = value.toLowerCase();
    } else if (key == 'integer_datetimes') {
      //if( value == "on"){}
    } else if (key == 'server_version') {
      //
    }
  }

  void _handleSocketError(dynamic error, {bool closed = false}) {
    print('_handleSocketError $error');

    if (state == ConnectionState.closed) {
      // _messages.add(new ClientMessageImpl(
      //     isError: false,
      //     severity: 'WARNING',
      //     message: 'Socket error after socket closed.',
      //     connectionName: _debugName,
      //     exception: error));
      _destroy();
      return;
    }
    _destroy();
    var msg = closed ? 'Socket closed unexpectedly.' : 'Socket error.';

    if (!hasConnected) {
      _connected.completeError(new PostgresqlException(msg, exception: error));
    } else {
      final query = _query;
      if (query != null) {
        query.addError(PostgresqlException(msg, exception: error));
        query.state = QueryState.done;
      } else {
        // _messages.add(new ClientMessage(
        //     isError: true,
        //     connectionName: debugName,
        //     severity: 'ERROR',
        //     message: msg,
        //     exception: error));
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
    var tempList = Utils.splitList<int>(data, NULL_BYTE);

    var msg = {};
    for (var bytes in tempList) {
      if (bytes.isNotEmpty) {
        msg[ascii.decode(bytes.sublist(0, 1))] = utf8.decode(bytes.sublist(1));
      }
    }
    var ex = PostgresqlException(msg['message'],
        serverMessage: msg, exception: msg['code']);

    print('handle_ERROR_RESPONSE $msg');

    if (!hasConnected) {
      state = ConnectionState.closed;
      this._usock.destroy();
      _connected.completeError(ex);
    } else {
      final query = _query;
      if (query != null) {
        query.addError(ex);
        query.state = QueryState.done;
      } else {
        // _messages.add(msg);

      }

      if (msg['code']?.startsWith('57P') ?? false) {
        //PG stop/restart
        final ow = owner;
        if (ow != null)
          ow.destroy();
        else {
          state = ConnectionState.closed;
          _usock.destroy();
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
        ));
        await c.close();
        _query = null;
      }
    }

    if (_usock == null) {
      throw Exception("connection is closed");
    }

    //send _MSG_TERMINATE
    try {
      _sock_write(TERMINATE_MSG);
      await _sock_flush();
    } finally {
      //
      await _usock.close();
      _usock = null;
    }
    print('CoreConnection closed');
  }

  void _destroy() {
    state = ConnectionState.closed;
    this._usock.destroy();
    // Timer.run(_messages.close);
  }
}

class QueryState {
  final int value;
  const QueryState(this.value);
  static const QueryState queued = const QueryState(1);
  static const QueryState busy = const QueryState(6);
  static const QueryState streaming = const QueryState(7);
  static const QueryState done = const QueryState(8);
}

class QueryType {
  final String value;
  const QueryType(this.value);
  static const QueryType prepareStatement = const QueryType('prepareStatement');
  static const QueryType unnamedStatement = const QueryType('unnamedStatement');
  static const QueryType namedStatement = const QueryType('namedStatement');
  static const QueryType simple = const QueryType('simple');
}

class Query {
  //statement
  final String sql;

  List<int> statement_name_bin;

  //dynamic stream;
  QueryState state = QueryState.queued;
  int commandIndex = 0;
  int rowsAffected = 0;

  /// params for prepared querys
  List _params;

  /// oids for prepared querys
  List _oids;

  /// se ouver params é uma Prepared query
  bool get isPrepared => _params != null || _params?.isEmpty == true;

  QueryType queryType = QueryType.simple;

  /// informa que terminaou a execução dos passos de uma prepared query
  bool isPreparedComplete = false;

  List get preparedParams => _params;
  List get oids => _oids;

  /// funções de conversão de tipo para as colunas
  List<Function> input_funcs = [];
  //List<List> _rows;
  int row_count;
  int columnCount;

  /// informações das colunas
  List<Map<String, dynamic>> columns;
  dynamic error;

  StreamController<dynamic> _controller = StreamController<dynamic>();
  Stream<dynamic> get stream => _controller.stream;

  void reInitStream() {
    _controller = StreamController<dynamic>();
  }

  Query(this.sql, [dynamic stream = null, columns = null, input_funcs = null]) {
    //
    //_rows = columns == null ? null : [];
    // if (columns != null) {
    //   initRows();
    // }
    row_count = -1;
    columns = columns;
    stream = stream;
    input_funcs = input_funcs == null ? [] : input_funcs;
    error = null;
  }

  void addPreparedParams(List params, [List oids]) {
    _params = params;
    _oids = oids;
    isPreparedComplete = false;
  }

  void addOids(List oids) {
    _oids = oids;
  }

  void addRow(List row) {
    row_count++;
    //_rows.add(row);
    _controller.add(row);
  }

  Future<void> close() async {
    await _controller.close();
    state = QueryState.done;
    print('Query@close');
  }

  void addError(Object err) {
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