import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:dargres/src/posgresql_types_models/geometric_data_types.dart';

void main(List<String> args) async {
  // user md5 = postgres
  //user scram = usarioscram
  //

  var sslContext = SslContext.createDefaultContext();

  var con = CoreConnection(
    'usermd5', //usarioscram usermd5 userscram //postgres
    database: 'sistemas', //sistemas
    host: 'localhost', //localhost
    port: 5432,
    password: 's1sadm1n', //s1sadm1n
    allowAttemptToReconnect: false,
    sslContext: sslContext,
  );

  // var con = CoreConnection('sw.suporte', //usarioscram //postgres
  //     database: 'siamweb', //'siamweb', //sistemas teste
  //     host: '192.168.66.4', //localhost 10.0.0.25
  //     port: 5432,
  //     password: 'suporte', //s1sadm1n
  //     textCharset: 'latin1'
  //     // sslContext: sslContext,
  //     );

  await con.connect();

  await con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;');
  await con.execute('CREATE SCHEMA IF NOT EXISTS myschema;');
  await con.execute('SET search_path TO myschema;');

  await con.execute('''
        CREATE TABLE "myschema"."postgresql_types" (
  -- "id" serial8 NOT NULL,
  "bit_type" bit(1),
  "bool_type" bool,
  "box_type" box,
  "bytea_type" bytea,
  "char_type" char(1) COLLATE "pg_catalog"."default",
  "cidr_type" cidr,
  "circle_type" circle,
  "date_type" date,
  "decimal_numeric_type" numeric(10),
  "float4_type" float4,
  "float8_type" float8,
  "inet_type" inet,
  "int2_type" int2,
  "int4_type" int4,
  "int8_type" int8,
  "interval_type" interval(6),
  "json_type" json,
  "jsonb_type" jsonb,
  "line_type" line,
  "lseg_type" lseg,
  "macaddr_type" macaddr,
  "money_type" money,
  "path_type" path,
  "point_type" point,
  "polygon_type" polygon,
  "text_type" text COLLATE "pg_catalog"."default",
  "time_type" time(6),
  "timestamp_type" timestamp(6),
  "timestamptz_type" timestamptz(6),
  "timetz_type" timetz(6),
  "tsquery_type" tsquery,
  "tsvector_type" tsvector,
 -- "txid_snapshot_type" txid_snapshot,
  "uuid_type" uuid,
  -- BIT VARYING() type
  "varbit_type" varbit(10),
  "varchar_type" varchar(255) COLLATE "pg_catalog"."default",
  "xml_type" xml,
  "xid_type" xid,
  varchar_array_type varchar[],
  int4_array_type int4[],
  bool_array_type bool[],
  bytea_array_type bytea[],
  char_array_type char[],
  date_array_type date[],
  float_array_type float[],
  json_array_type json[],
  jsonb_array_type jsonb[],
  money_array_type money[],
  numeric_array_type numeric[],
  interval_array_type interval[],
  text_array_type text[],
  time_array_type time[],
  timestamp_array_type timestamp[],
  timestamptz_array_type timestamptz[],
  uuid_array_type uuid[],
  int2vector_type int2vector,
  int8_array_type int8[],
  int2_array_type int2[],
  cidr_array_type cidr[],
  inet_array_type inet[],
  xml_array_type xml[],
  varbit_array_type varbit[],
  oid_type OID,
  oid_array_type OID[]
  
);
        ''');

  await con.querySimple(r'''
INSERT INTO postgresql_types
(
  bit_type, bool_type, box_type, bytea_type, char_type, cidr_type, circle_type, date_type, decimal_numeric_type, float4_type,float8_type,inet_type
,int2_type, int4_type, int8_type, interval_type, json_type, jsonb_type, line_type, lseg_type, macaddr_type,
 money_type,
path_type, point_type, polygon_type, text_type, time_type, timestamp_type, timestamptz_type, timetz_type, tsquery_type, 
tsvector_type, uuid_type, varbit_type, varchar_type, 
xml_type, 
xid_type, varchar_array_type, int4_array_type, bool_array_type, bytea_array_type, char_array_type, date_array_type, float_array_type,
json_array_type, jsonb_array_type, money_array_type, numeric_array_type, interval_array_type, text_array_type, time_array_type,
timestamp_array_type, timestamptz_array_type, uuid_array_type, int2vector_type, int8_array_type, int2_array_type, cidr_array_type,
inet_array_type, xml_array_type, varbit_array_type, oid_type, oid_array_type
 )
 VALUES 
( 
  B'10'::bit(1), true, '(0,0),(1,1)', E'\\336\\255\\276\\357'::bytea,'A', '192.168.100.128/25', '<(1,1),2>' ,'2022-12-19', 5, 2.3, 500.50 ,'192.168.0.0/24'
,2, 4, 8, '3 days 04:05:06'::interval, '{"key":"value"}', '{"key":"value"}', '(2,3),(4,7)', '(2,3),(4,7)','08:00:2b:01:02:03' , 
'25',
'(2,3),(4,7)', '(2,3)', '(2,3),(4,7)', 'text example', '19:50', '2022-12-21T15:52:00', '2022-12-21T15:52:00', '14:24', 'fat & rat',
'a fat'::tsvector, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',  (X'A'), 'varchar test', 
'<?xml version="1.0"?><book><title>Manual</title><chapter>...</chapter></book>',
'123'::xid, '{"a","b"}', '{1,2,null}', '{true,false,null}', '{"\\336\\255\\276\\357",null}', '{a,b}', '{"2022-12-19"}', '{10.5,1.3}',
array['{"sender":"pablo","body":"us"}']::json[], array['{"sender":"pablo"}']::json[], '{10.50}', '{11.50}', '{"3 days 04:05:06"}', '{"abc"}', '{"19:00"}',
'{"2022-12-21T15:52:00"}', '{"2022-12-21T15:52:00"}', '{"a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', '2', '{8,8}', '{2,2}', '{"192.168.100.128/25"}',
'{"192.168.100.128/25"}', array['<?xml version="1.0"?><title>Manual</title>']::xml[], array[(X'A')]::varbit[], 2, '{2,2}'
);''', []);

  var results = await con.querySimple(r'''SELECT *
       FROM postgresql_types;''', []);

  for (var row in results) {
    var cols = row.map((c) => '$c' + ' ${c.runtimeType}\r\n').join('');
    print("row: $cols");
  }

  // var count = 0;
  // Timer.periodic(Duration(milliseconds: 3000), (t) async {
  //   try {
  //     var result = await con.executeSimple('select $count').toList();
  //     print('result: $result');
  //   } on PostgresqlException catch (e, s) {
  //     print('PostgresqlException e: ${e} ');
  //   } catch (e) {
  //     print('result e: ${e}');
  //   }
  //   count++;
  // });

  // var count2 = 0;
  // Timer.periodic(Duration(milliseconds: 2000), (t) async {
  //   try {
  //     var result = await con.executeSimple("select 'abc'").toList();
  //     print('result letra: $result');
  //   } on PostgresqlException catch (e, s) {
  //     print('PostgresqlException e: ${e} ');
  //   } catch (e) {
  //     print('result e: ${e}');
  //   }
  //   count2++;
  // });

  // // //observacoes,resumo_assunto
  // var res = await con.executeSimple('''select *
  //     from protocolo.processo_historico
  //     where ano_exercicio=2022 AND cod_processo=590 limit 1''').toList();

  // print('main ${res}');
//   var res = await con.execute('''
//   INSERT INTO teste_table (name) VALUES ('João')
// ''');
//   print('main ${res}');

//   res = await con.execute(r'''
//   INSERT INTO teste_table (name) VALUES ($1)
// ''', ['João']);
//   print('main ${res}');

  // var res2 =
  //     await con.executeSimple(''' SELECT * FROM teste_table  ''').toList();
  // print('main ${res2}');

  //var tyc = TypeConverter('utf8', null);

  // con.notifications.listen((event) async {
  //   print('$event');
  // });

  // await con.execute('LISTEN "db_change_event"');
  // Timer.periodic(Duration(seconds: 2), (t) async {
  //   await con.execute("NOTIFY db_change_event, 'This is the payload'");
  // });

  // Timer.periodic(Duration(milliseconds: 2000), (t) async {
  // final transa = await con.beginTransaction();
  // try {
  //   await transa.executeSimple(
  //       """INSERT INTO "crud_teste"."pessoas" ("nome", "dataCadastro", "cpf") VALUES ('Alex', '2022-11-30 16:22:03', '171') returning id""").toList();
  //   await con.commit(transa);
  // } catch (e) {
  //   await con.rollBack(transa);
  // }

  // await con.runInTransaction((ctx) async {
  //   return ctx.executeSimple(
  //       """INSERT INTO "crud_teste"."pessoas" ("nome", "dataCadastro", "cpf") VALUES ('Alex', '2022-11-30 16:22:03', '171') returning id""").toList();
  // });
  //   print('periodic2 fim');
  // });

  // Timer.periodic(Duration(milliseconds: 1000), (t) async {
  // var items = con.execute_simple('select * from crud_teste.cursos limit 2');
  // await for (var item in items) {
  //   print(item);
  // }
  //});
  // Timer.periodic(Duration(milliseconds: 1000), (t) async {
  //   items =
  //       con.execute_unnamed('select * from crud_teste.pessoas limit \$1', [1]);
  //   await for (var item in items) {
  //     print('item: $item | ${item.map((i) => i.runtimeType).toList()}');
  //   }
  // });
  // var rowsAffected = await con.execute("START TRANSACTION");
  // rowsAffected = await con.execute("DELETE FROM crud_teste.pessoas WHERE id=4");
  // rowsAffected = await con.execute("ROLLBACK");

  // Timer.periodic(Duration(milliseconds: 1000), (t) async {
  //   var items = con.executeSimple('select * from crud_teste.cursos limit 2');
  //   await for (var item in items) {
  //     print(item);
  //   }
  // });
  // var query =
  //     await con.prepareStatement('select * from crud_teste.people limit \$1');
  // query.addPreparedParams([1]);
  // print('fim prepare_statement');
  // var items = await con.executeNamed(query).toList();
  // print('result: $items');
  // print('sql: ${query.sql}');

  // var count = 0;
  // Timer.periodic(Duration(seconds: 4), (t) async {
  //   //await con.execute('select * from crud_teste.cursos limit \$1', [1]);

  //   var query = await con
  //       .prepare_statement('select * from crud_teste.pessoas limit \$1');
  //   query.addPreparedParams([1]);
  //   print('fim prepare_statement');

  //   //  print('Timer.periodic $query ');

  //   var items = await con.execute_named(query).toList();
  //   print('fim execute_named $items');
  //   // print('fim execute_named ${query.sql}');

  //   if (count == 100) {
  //     t.cancel();
  //   }
  //   count++;
  // });

  // var count2 = 0;
  // Timer.periodic(Duration(seconds: 2), (t) async {
  //   //await con.execute('select * from crud_teste.cursos limit \$1', [1]);

  //   var query = await con
  //       .prepare_statement('select * from crud_teste.cursos limit \$1');
  //   query.addPreparedParams([1]);
  //   print('fim prepare_statement');

  //   // print('Timer.periodic $query ');

  //   var items = await con.execute_named(query).toList();
  //   print('fim execute_named $items');
  //   // print('fim execute_named ${query.sql}');

  //   if (count2 == 100) {
  //     t.cancel();
  //   }
  //   count2++;
  // });

  await con.close();

  exit(0);
}
