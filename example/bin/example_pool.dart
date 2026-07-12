import 'dart:io';

import 'package:dargres/dargres.dart';

String _environment(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

Future<void> main() async {
  final settings = ConnectionSettings(
    user: _environment('PGUSER', 'dart'),
    password: _environment('PGPASSWORD', 'dart'),
    database: _environment('PGDATABASE', 'postgres'),
    host: _environment('PGHOST', 'localhost'),
    port: int.parse(_environment('PGPORT', '5432')),
    applicationName: 'dargres_pool_example',
  );
  final pool = PostgreSqlPool(4, settings);

  try {
    final rows = await pool.queryMaps('SELECT version() AS version');
    print(rows.single['version']);
  } finally {
    await pool.close();
  }
}
