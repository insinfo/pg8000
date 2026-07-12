import 'dart:io';

import 'package:dargres/src/core.dart';
import 'package:dargres/src/timezone_settings.dart';
import 'package:test/test.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

void main() {
  test('text and binary timestamptz preserve historical IANA transitions',
      () async {
    const timeZone = TimeZoneSettings(
      'America/Sao_Paulo',
      forceDecodeTimestamptzAsUTC: false,
      useIanaTimeZoneDatabase: true,
    );
    final connection = CoreConnection(
      _environment('PGUSER', 'dart'),
      database: _environment('PGDATABASE', 'postgres'),
      host: _environment('PGHOST', 'localhost'),
      port: int.parse(_environment('PGPORT', '5432')),
      password: _environment('PGPASSWORD', 'dart'),
      timeZone: timeZone,
    );
    addTearDown(connection.close);
    await connection.connect();

    const sql =
        "SELECT TIMESTAMPTZ '2000-01-15 12:00:00+00' AS historical, "
        "TIMESTAMPTZ '2024-07-12 15:00:00+00' AS recent";
    final cold = await connection.queryMaps(sql);
    final warm = await connection.queryMaps(sql);

    for (final row in <Map<String, dynamic>>[cold.single, warm.single]) {
      final historical = row['historical'] as DateTime;
      final recent = row['recent'] as DateTime;
      expect(historical.toUtc(), DateTime.utc(2000, 1, 15, 12));
      expect(historical.timeZoneOffset, const Duration(hours: -2));
      expect(recent.toUtc(), DateTime.utc(2024, 7, 12, 15));
      expect(recent.timeZoneOffset, const Duration(hours: -3));
    }
  });

  test('warm statement follows SET TIME ZONE without rebuilding its schema',
      () async {
    const timeZone = TimeZoneSettings(
      'America/Sao_Paulo',
      forceDecodeTimestamptzAsUTC: false,
      useIanaTimeZoneDatabase: true,
    );
    final connection = CoreConnection(
      _environment('PGUSER', 'dart'),
      database: _environment('PGDATABASE', 'postgres'),
      host: _environment('PGHOST', 'localhost'),
      port: int.parse(_environment('PGPORT', '5432')),
      password: _environment('PGPASSWORD', 'dart'),
      timeZone: timeZone,
    );
    addTearDown(connection.close);
    await connection.connect();

    const sql =
        "SELECT TIMESTAMPTZ '2024-01-15 12:00:00+00' AS instant";
    final cold = (await connection.queryMaps(sql)).single['instant'] as DateTime;
    final warm = (await connection.queryMaps(sql)).single['instant'] as DateTime;
    expect(cold.timeZoneOffset, const Duration(hours: -3));
    expect(warm.timeZoneOffset, const Duration(hours: -3));
    expect(connection.statementCacheLength, 1);
    final hitsBeforeChange = connection.statementCacheHits;

    await connection.execute("SET TIME ZONE 'America/New_York'");
    expect(connection.serverInfo.timeZone.value, 'America/New_York');

    final reused =
        (await connection.queryMaps(sql)).single['instant'] as DateTime;
    expect(connection.statementCacheHits, hitsBeforeChange + 1,
        reason: 'The statement and its ResultSchema must be reused.');
    expect(connection.statementCacheLength, 1);
    expect(reused.toUtc(), DateTime.utc(2024, 1, 15, 12));
    expect(reused.timeZoneOffset, const Duration(hours: -5));
    expect(reused.hour, 7);
  });
}
