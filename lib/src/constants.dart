import 'dart:typed_data';

const int nullByte = 0;

// Message Formats
//https://www.postgresql.org/docs/current/protocol-message-formats.html
const int noticeResponse = 78;
const int authenticationRequest = 82;
const int parameterStatus = 83;
const int backendKeyData = 75;
const int readyForQuery = 90;
const int rowDescription = 84;
const int errorResponse = 69;
const int dataRow = 68;
const int commandComplete = 67;
const int parseComplete = 49;
const int closeComplete = 51;
const int parameterDescription = 116;
const int notificationResponse = 65;
const int copyData = 100;
const int functionCallResponse = 86;

const int bindMessage = 66;
const int parseMessage = 80;
const int queryMessage = 81;
const int executeMessage = 69;
const int syncMessage = 83;
const int passwordMessage = 112;
const int describeMessage = 68;
const int terminateMessageCode = 88;
const int closeMessage = 67;

/// PostgreSQL CancelRequest protocol code (1234 << 16 | 5678).
const int cancelRequestCode = 80877102;

Uint8List int32Bytes(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setInt32(0, value, Endian.big);
  return bytes;
}

/// Builds the fixed-size startup packet used to cancel the command currently
/// running on a backend. It is sent over a separate, short-lived connection.
Uint8List cancelRequestBytes(int processId, int secretKey) {
  final bytes = Uint8List(16);
  final data = ByteData.sublistView(bytes);
  data
    ..setInt32(0, 16, Endian.big)
    ..setInt32(4, cancelRequestCode, Endian.big)
    ..setInt32(8, processId, Endian.big)
    ..setInt32(12, secretKey, Endian.big);
  return bytes;
}

int int32FromBytes(List<int> bytes, [int offset = 0]) {
  if (offset < 0 || offset + 4 > bytes.length) {
    throw RangeError.range(offset, 0, bytes.length - 4, 'offset');
  }
  return ((bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3])
      .toSigned(32);
}

List<int> _createMessage(int code, [List<int> bytes = const <int>[]]) {
  return [code, ...int32Bytes(bytes.length + 4), ...bytes];
}

final List<int> terminateMessage = _createMessage(terminateMessageCode);

// Describe target discriminator.
const int statementTarget = 83;

const int idleStatus = 73;
const int inTransactionStatus = 84;
const int inFailedTransactionStatus = 69;
