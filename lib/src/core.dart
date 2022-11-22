// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:pg8000/src/utils/utils.dart';

import 'utils/buffer.dart';
import 'connection_state.dart';

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

  final _connected = Completer<CoreConnection>();

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

  Future<dynamic> Function() _flush;

  void Function(List<int> d) _write;

  ///  Int32(196608) - Protocol version number.  Version 3.0.
  int protocol = 196608;

  Map<String, dynamic> init_params = <String, dynamic>{};

  List<int> _backend_key_data;

  Map<dynamic, dynamic> message_types = <dynamic, dynamic>{};

  List<int> _transaction_status;

  ConnectionState state = ConnectionState.notConnected;

  Buffer _buffer;

  int _backendPid;

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
    init();
  }

  void init() {
    if (user == null) {
      throw Exception("The 'user' connection parameter cannot be None");
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

    this._flush = _sock_flush;
    this._write = _sock_write;

    message_types = {
      NOTICE_RESPONSE: this.handle_NOTICE_RESPONSE,
      AUTHENTICATION_REQUEST: this.handle_AUTHENTICATION_REQUEST,
    };
  }

  void _send_message(int code, List<int> data) {
    try {
      this._write([code]);
      this._write(i_pack(Utils.len(data) + 4));
      this._write(data);
    } catch (e) {
      throw Exception("_send_message connection is closed $e");
    }
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
        throw Exception(
            """Can't create a connection to host $host and port $port 
                    (timeout is $timeout and source_address is $source_address).""");
      }
    } else if (unix_sock != null) {
      throw UnimplementedError('unix_sock not implemented');
    } else {
      throw Exception("one of host or unix_sock must be provided");
    }

    if (ssl_context != null) {
      throw UnimplementedError('ssl_context not implemented');
    }

    this._usock.listen(_readData,
        onError: _handleSocketError, onDone: _handleSocketClosed);
    _sendStartupMessage();

    return _connected.future;
  }

  Future<dynamic> _sock_flush() {
    try {
      return this._usock.flush();
    } catch (e) {
      throw Exception("_sock_flush network error");
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

  void _sendStartupMessage() async {
    print('CoreConnection@_sendStartupMessage');
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
    this._write(i_pack(Utils.len(val) + 4));
    this._write(val);
    await this._flush();
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

    var context = Context(null);

    while (state != ConnectionState.closed) {
      if (_buffer.bytesAvailable < 5) return; // Wait for more data.

      int msgType = _buffer.readByte();
      int length = _buffer.readInt32() - 4;

      print('_readData code: $msgType');
      var messageBytes = _buffer.readBytes(length);

      //print('READY_FOR_QUERY, ERROR_RESPONSE');
      switch (msgType) {
        case NOTICE_RESPONSE:
          print('NOTICE_RESPONSE');
          break;
        case AUTHENTICATION_REQUEST:
          await handle_AUTHENTICATION_REQUEST(messageBytes, context);
          break;
        case PARAMETER_STATUS:
          handle_PARAMETER_STATUS(messageBytes, context);
          break;
        case BACKEND_KEY_DATA:
          handle_BACKEND_KEY_DATA(messageBytes, context);
          break;
        case READY_FOR_QUERY:
          handle_READY_FOR_QUERY(messageBytes, context);
          break;

        case ERROR_RESPONSE:
          handle_ERROR_RESPONSE(messageBytes, context);
          break;
        case ROW_DESCRIPTION:
          handle_ROW_DESCRIPTION(messageBytes, context);
          break;
      }
      //[READY_FOR_QUERY, ERROR_RESPONSE].contains(code)
    }
  }

  void handle_ERROR_RESPONSE(List<int> data, Context context) {
    var tempList = Utils.splitList<int>(data, NULL_BYTE);

    var msg = {};
    for (var bytes in tempList) {
      if (bytes.isNotEmpty) {
        msg[ascii.decode(bytes.sublist(0, 1))] = utf8.decode(bytes.sublist(1));
      }
    }
    print('handle_ERROR_RESPONSE $msg');
    context.error = Exception(msg);
  }

  void handle_BACKEND_KEY_DATA(List<int> data, Context context) {
    this._backend_key_data = data;
    _backendPid = i_unpack(data).first;
    print('handle_BACKEND_KEY_DATA _backendPid ${_backendPid}');
  }

  void handle_READY_FOR_QUERY(List<int> data, Context context) {
    print('handle_READY_FOR_QUERY ${data}');
    this._transaction_status = data;
    var was = state;
    state = ConnectionState.idle;

    if (was == ConnectionState.authenticated) {
      //_hasConnected = true;
      _connected.complete(this);
    }
  }

  void handle_ROW_DESCRIPTION(List<int> data, Context context) {
    print('handle_ROW_DESCRIPTION ');
    state = ConnectionState.streaming;
    var count = h_unpack(data)[0];
    var idx = 2;
    List<Map<String, dynamic>> columns = [];
    var input_funcs = [];

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
    }
    context.columns = columns;
    print(columns);
  }

  Future<Context> execute_simple(statement) async {
    var context = Context(statement);
    print('execute_simple $statement');
    this.send_QUERY(statement);
    await this._flush();
    //this.handle_messages(context);

    return context;
  }

  dynamic send_QUERY(String sql) {
    this._send_message(QUERY, [...utf8.encode(sql), NULL_BYTE]);
  }

  void handle_NOTICE_RESPONSE(List<int> data, Context context) {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    //this.notices.add({s[0:1]: s[1:] for s in data.split(NULL_BYTE)});
  }

  Future<void> handle_AUTHENTICATION_REQUEST(
      List<int> data, Context context) async {
    //https://www.postgresql.org/docs/current/protocol-message-formats.html
    print('handle_AUTHENTICATION_REQUEST');

    var auth_code = i_unpack(data)[0];
    print('auth_code: $auth_code');
    if (auth_code == 0) {
      state = ConnectionState.authenticated;
      return;
    } else if (auth_code == 3) {
      if (this.password == null)
        throw Exception(
            "server requesting password authentication, but no password was " +
                "provided");
      this._send_message(PASSWORD, [...this.passwordBytes, NULL_BYTE]);
      await this._flush();
    } else if (auth_code == 5) {
      if (this.password == null) {
        throw Exception(
            "server requesting MD5 password authentication, but no password "
            "was provided");
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
      await this._flush();
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
      throw Exception(
          "Authentication method $auth_code not supported by pg8000.");
    else {
      throw Exception(
          "Authentication method $auth_code not recognized by pg8000.");
    }
  }

  /// obtem as informações do servidor
  void handle_PARAMETER_STATUS(List<int> data, Context context) {
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

  List<int> _sock_read(List<int> socketData, int size, [int offset = 0]) {
    if (offset != 0) {
      return socketData.sublist(offset).sublist(0, size);
    }
    return socketData.sublist(0, size);
  }

  void _handleSocketError(dynamic error, {bool closed = false}) {
    print('_handleSocketError $error');
  }

  void _handleSocketClosed() {
    print('_handleSocketClosed');
  }
}

class Context {
  dynamic statement;
  dynamic stream;
  dynamic input_funcs;
  dynamic rows;
  dynamic row_count;
  List<Map<String, dynamic>> columns;
  dynamic error;

  Context(this.statement,
      [dynamic stream = null, columns = null, input_funcs = null]) {
    this.rows = columns == null ? null : [];
    row_count = -1;
    columns = columns;
    stream = stream;
    input_funcs = input_funcs == null ? [] : input_funcs;
    error = null;
  }
}
