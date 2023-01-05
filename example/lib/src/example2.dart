import 'package:dargres/dargres.dart';

void example1() async {
  var sslContext = SslContext.createDefaultContext();

  var con = CoreConnection(
    'usermd5',
    database: 'sistemas',
    host: 'localhost',
    port: 5432,
    password: 's1sadm1n',
    allowAttemptToReconnect: false,
    sslContext: sslContext,
  );

  await con.connect();
  await con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;');
  await con.execute('CREATE SCHEMA IF NOT EXISTS myschema;');
  await con.execute('SET search_path TO myschema;');

  await con.execute('''
        CREATE TABLE "myschema"."test_arrays" ( 
          name NAME,
  varchar_array_type varchar[], 
  int8_array_type int8[],
  int2_array_type int2[],
  names_array_type NAME[]  
);
        ''');

  await con.runInTransaction((ctx) async {
    await ctx.queryUnnamed(
      'INSERT INTO test_arrays (name, varchar_array_type) VALUES (@name, @varchars);',
      {
        'name': 'Vagner',
        'varchars': ["João", '''Isaque Sant'Ana''']
      },
      placeholderIdentifier: PlaceholderIdentifier.atSign,
    );
  });
   await con
      .querySimple('SELECT name, varchar_array_type FROM test_arrays limit 1;');
}
