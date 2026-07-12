import 'dart:typed_data';

import 'package:dargres/src/constants.dart';
import 'package:test/test.dart';

void main() {
  test('CancelRequest encodes length, code, pid and secret in network order',
      () {
    final packet = cancelRequestBytes(0x01020304, -2);
    final data = ByteData.sublistView(packet);

    expect(packet, hasLength(16));
    expect(data.getInt32(0, Endian.big), 16);
    expect(data.getInt32(4, Endian.big), cancelRequestCode);
    expect(data.getInt32(8, Endian.big), 0x01020304);
    expect(data.getInt32(12, Endian.big), -2);
  });
}
