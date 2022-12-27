import 'pack_unpack.dart';

const int NULL_BYTE = 0; // b"\x00"

// Message Formats
//https://www.postgresql.org/docs/current/protocol-message-formats.html
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
const int NO_DATA = 110; //b"n"
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

    case AUTHENTICATION_REQUEST:
      return 'AUTHENTICATION_REQUEST';

    case PARAMETER_STATUS:
      return 'PARAMETER_STATUS';

    case BACKEND_KEY_DATA:
      return 'BACKEND_KEY_DATA';

    case READY_FOR_QUERY:
      return 'READY_FOR_QUERY';

    case ROW_DESCRIPTION:
      return 'ROW_DESCRIPTION';

    case ERROR_RESPONSE:
      return 'ERROR_RESPONSE';

    case DATA_ROW:
      return 'DATA_ROW';

    case COMMAND_COMPLETE:
      return 'COMMAND_COMPLETE';

    case PARSE_COMPLETE:
      return 'PARSE_COMPLETE';

    case BIND_COMPLETE:
      return 'BIND_COMPLETE';

    case CLOSE_COMPLETE:
      return 'CLOSE_COMPLETE';

    case PORTAL_SUSPENDED:
      return 'PORTAL_SUSPENDED';

    case NO_DATA:
      return 'NO_DATA';

    case PARAMETER_DESCRIPTION:
      return 'PARAMETER_DESCRIPTION';

    case NOTIFICATION_RESPONSE:
      return 'NOTIFICATION_RESPONSE';

    case COPY_DONE:
      return 'COPY_DONE';

    case COPY_DATA:
      return 'COPY_DATA';

    case COPY_IN_RESPONSE:
      return 'COPY_IN_RESPONSE';

    case COPY_OUT_RESPONSE:
      return 'COPY_OUT_RESPONSE';

    case EMPTY_QUERY_RESPONSE:
      return 'EMPTY_QUERY_RESPONSE';
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