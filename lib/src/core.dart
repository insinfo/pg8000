// ignore_for_file: deprecated_member_use

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:pg8000/src/utils/utils.dart';

import 'utils/buffer.dart';

import 'dart:cli';

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

List<int> unpack(String fmt, List<int> bytes) {
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
  buffer.append(bytes);

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

List<int> i_unpack(List<int> bytes) {
  return unpack('i', bytes);
}

List<int> h_pack(int val) {
  return pack('h', [val]);
}

List<int> h_unpack(List<int> bytes) {
  return unpack('h', bytes);
}

List<int> ii_pack(int val1, int val2) {
  return pack('ii', [val1, val2]);
}

List<int> ii_unpack(List<int> bytes) {
  return unpack('ii', bytes);
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
  List<int> user;
  String host;
  String database;
  int port;
  List<int> password;
  dynamic source_address;
  dynamic unix_sock;
  dynamic ssl_context;
  dynamic timeout;
  bool tcp_keepalive;
  String application_name;
  dynamic replication;

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
  Queue parameter_statuses = Queue();

  String userP;
  String passwordP;

  Duration connectionTimeout = Duration(seconds: 180);

  dynamic channel_binding;

  Future<dynamic> Function() _flush;

  CoreConnection(
    this.userP, {
    this.host = "localhost",
    this.database,
    this.port = 5432,
    this.passwordP,
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
    if (userP == null) {
      throw Exception("The 'user' connection parameter cannot be None");
    }

    var init_params = <String, dynamic>{
      "user": userP,
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
    this.parameter_statuses = Queue();

    this.user = init_params["user"];

    if (passwordP is String) {
      this.password = utf8.encode(passwordP);
    }

    this.autocommit = false;
    this._xid = null;
    this._statement_nums = Set();
    this._caches = {};

    this._flush = sock_flush;
  }

  Future<void> connect() async {
    if (unix_sock == null && host != null) {
      try {
        //TODO remover waitFor no futuro
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
      } catch (e) {
        print('CoreConnection $e');
        throw Exception(
            """Can't create a connection to host {host} and port {port} 
                    (timeout is {timeout} and source_address is {source_address}).""");
      }
    } else if (unix_sock != null) {
      throw UnimplementedError('unix_sock not implemented');
    } else {
      throw Exception("one of host or unix_sock must be provided");
    }

    if (ssl_context != null) {
      throw UnimplementedError('ssl_context not implemented');
    }
  }

  Future<dynamic> sock_flush() {
    try {
      this._usock.flush();
    } catch (e) {
      throw Exception("network error");
    }
  }
}
