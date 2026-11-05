// The password goes in clear text only to a verified server or by explicit
// choice. A fake server on loopback asks for it; no database needed.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

const _password = 'secret-password';

List<int> _message(String type, List<int> body) {
  final length = ByteData(4)..setInt32(0, body.length + 4);
  return [type.codeUnitAt(0), ...length.buffer.asUint8List(), ...body];
}

final _askCleartext = _message('R', [0, 0, 0, 3]);
final _refused = _message('E', [
  ...latin1.encode('SFATAL\x00VFATAL\x00C28P01\x00Mrefused by fake server\x00'),
  0,
]);

void main() {
  late ServerSocket server;
  late bool received;

  setUp(() async {
    received = false;
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((client) {
      client.listen((chunk) {
        if (utf8.decode(chunk, allowMalformed: true).contains(_password)) {
          received = true;
          client.add(_refused);
        } else {
          client.add(_askCleartext);
        }
      }, onError: (_) {});
    });
  });

  tearDown(() => server.close());

  Future<Object?> connect({bool allow = false}) async {
    final core = CoreConnection.fromSettings(ConnectionSettings(
      user: 'user',
      database: 'db',
      host: 'localhost',
      port: server.port,
      password: _password,
      connectionTimeout: const Duration(seconds: 3),
      allowCleartextPassword: allow,
    ));
    Object? error;
    try {
      await core.connect();
    } catch (e) {
      error = e;
    }
    try {
      await core.close();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return error;
  }

  test('not sent by default', () async {
    final error = await connect();
    expect('$error', contains('clear text'));
    expect(received, isFalse);
  });

  test('sent with allowCleartextPassword', () async {
    final error = await connect(allow: true);
    expect('$error', contains('refused by fake server'));
    expect(received, isTrue);
  });

  test('clone() keeps the setting', () {
    final settings = ConnectionSettings(
        user: 'user', allowCleartextPassword: true);
    expect(settings.clone().allowCleartextPassword, isTrue);
    expect(ConnectionSettings(user: 'user').allowCleartextPassword, isFalse);
  });
}
