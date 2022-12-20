import 'package:dargres/dargres.dart';
import 'package:dargres/src/core.dart';

import 'package:test/test.dart';

void main() {
  var con = CoreConnection('postgres',
      database: 'sistemas',
      host: 'localhost',
      port: 5432,
      password: 's1sadm1n',
      textCharset: 'latin1');

  setUp(() async {
    await con.connect();
    await con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;');
    await con.execute('CREATE SCHEMA IF NOT EXISTS myschema;');
    await con.execute('SET search_path TO myschema;');

    await con.execute('''CREATE TABLE IF NOT EXISTS myschema.pessoas_cursos (
      "id" serial8 NOT NULL,
      "idPessoa" int8,
      "idCurso" int8,
      "name" varchar(255),
      CONSTRAINT "pessoas_cursos_pkey" PRIMARY KEY ("id")
    );''');
  });

  group('test query', () {
    // test('test database error', () async {
    //   // var res = await con.execute("INSERT INTO t99 VALUES (1, 2, 3)");
    //   expect(con.execute('INSERT INTO t99 VALUES (1, 2, 3)'),
    //       throwsA(isA<PostgresqlException>()));
    // });

    test('test select clear', () async {
      await con.execute("CREATE TEMPORARY TABLE t1 (f1 int primary key, "
          "f2 bigint not null, f3 varchar(50) null) ");
      try {
        await con.execute('INSERT INTO t99 VALUES (1, 2, 3)');
      } catch (e) {
        //
      }
      var res = await con.querySimple('select * from t1');
      expect(res, []);
    });
    test('test runInTransaction INSERT', () async {
      await con.runInTransaction((ctx) async {
        var statement = await ctx.prepareStatement(
            r'''INSERT INTO "myschema"."pessoas_cursos" ("idPessoa", "idCurso","name") VALUES ($1, $2 ,$3)''',
            [10, 3, 'Isaque']);
        await ctx.executeStatement(statement);
      });
      var result = await con
          .querySimple('select * from "myschema"."pessoas_cursos" limit 1');

      expect(result, [
        [1, 10, 3, 'Isaque']
      ]);
    });

    test('test runInTransaction INSERT with failure', () async {
      expect(con.runInTransaction((ctx) async {
        var statement = await ctx.prepareStatement(
            r'''INSERT INTO "myschema"."pessoas_cursos" ("idPessoa", "idCurso","name2") VALUES ($1, $2 ,$3)''',
            [10, 3, 'Isaque']);
        await ctx.executeStatement(statement);
      }), throwsA(isA<PostgresqlException>()));
    });
  });

  test('test Bit String Types', () async {
    await con.execute(
        ''' CREATE TEMPORARY TABLE test_bit (a BIT(3), b BIT VARYING(5)); ''');

    await con.querySimple(
        r'''INSERT INTO test_bit VALUES (B'10'::bit(3), B'101');''', []);

    var result = await con.querySimple(r'''SELECT * FROM test_bit;''', []);

    expect(result, [
      ['100', '101']
    ]);
  });

  test('test all posgresql Types', () async {
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
  "txid_snapshot_type" txid_snapshot,
  "uuid_type" uuid,
  "varbit_type" varbit(10),
  "varchar_type" varchar(255) COLLATE "pg_catalog"."default",
  "xml_type" xml
);        
        ''');
    //decode('DEADBEEF', 'hex')::bytea
    //https://stackoverflow.com/questions/3103242/inserting-text-string-with-hex-into-postgresql-as-a-bytea
    //https://www.informit.com/articles/article.aspx?p=24662
    await con.querySimple(r'''
INSERT INTO postgresql_types
(bit_type, bool_type, box_type, bytea_type, char_type, cidr_type, circle_type, date_type)
 VALUES 
( B'10'::bit(1), true, '(0,0),(1,1)', E'\\336\\255\\276\\357'::bytea,'A', '192.168.100.128/25', '<(1,1),2>' ,'2022-12-19' );''',
        []);

    var result =
        await con.querySimple(r'''SELECT * FROM postgresql_types;''', []);

    expect(result, [
      ['100', '101']
    ]);
  });
}
