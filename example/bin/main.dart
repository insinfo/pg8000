
import 'dart:io';
import 'package:dargres/dargres.dart';


void main(List<String> args) async {

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
          nome NAME,
  varchar_array_type varchar[], 
  int8_array_type int8[],
  int2_array_type int2[],
  names_array_type NAME[]  
);
        ''');

  await con.queryUnnamed(r'''
INSERT INTO test_arrays
(nome, varchar_array_type,int8_array_type, int2_array_type, names_array_type)
 VALUES 
($1, $2, $3, $4, $5);
''', ['Vagner',["João",'''Isaque Sant'Ana'''],[1,2,3],[1,2,3],['name1']]);

  var results = await con.querySimple(r'''SELECT * FROM test_arrays;''');

  for (var row in results) {
    // var cols = row.map((c) => '$c' + ' ${c.runtimeType}\r\n').join('');
    // print("$cols");
    print(row.toColumnMap());
  }
 

  await con.close();

  exit(0);
}
