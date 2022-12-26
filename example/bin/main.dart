
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

  

  await con.close();

  exit(0);
}
