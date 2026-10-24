// TLS against the local server (it has ssl = on): the SSLRequest answer is
// read from the socket, which must then be handed to SecureSocket.secure.
// The subscription used to be cancelled first, so every handshake failed
// with "Connection terminated during handshake".
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:test/test.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

ConnectionSettings _settings({SslContext? sslContext}) => ConnectionSettings(
      user: _environment('PGUSER', 'dart'),
      password: _environment('PGPASSWORD', 'dart'),
      database: _environment('PGDATABASE', 'postgres'),
      host: _environment('PGHOST', 'localhost'),
      port: int.parse(_environment('PGPORT', '5432')),
      sslContext: sslContext,
    );

Future<bool> _serverHasSsl() async {
  final connection = CoreConnection.fromSettings(_settings());
  await connection.connect();
  try {
    final rows = await connection.queryMaps('SHOW ssl');
    return rows.single.values.first == 'on';
  } finally {
    await connection.close();
  }
}

void main() {
  late bool serverHasSsl;

  setUpAll(() async {
    serverHasSsl = await _serverHasSsl();
  });

  test('a TLS connection is encrypted and runs queries', () async {
    if (!serverHasSsl) {
      markTestSkipped('the server has ssl = off');
      return;
    }
    final connection = CoreConnection.fromSettings(
        _settings(sslContext: SslContext.createDefaultContext()));
    await connection.connect();
    addTearDown(connection.close);

    final rows = await connection
        .queryMaps('select ssl from pg_stat_ssl where pid = pg_backend_pid()');
    expect(rows.single['ssl'], isTrue);
    final value = await connection.queryMaps("select 'ção' as v, 42 as n");
    expect(rows, isNotEmpty);
    expect(value.single['v'], 'ção');
    expect(value.single['n'], 42);
  });

  test('a rejected certificate fails the connection, not later queries',
      () async {
    if (!serverHasSsl) {
      markTestSkipped('the server has ssl = off');
      return;
    }
    final connection = CoreConnection.fromSettings(
        _settings(sslContext: SslContext(onBadCertificate: (_) => false)));
    await expectLater(connection.connect(), throwsA(anything));
    await connection.close();
  });
}
