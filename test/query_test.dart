import 'dart:io';

import 'package:dargres/dargres.dart';
//import 'package:dargres/src/core.dart';
import 'package:test/test.dart';

//dart test .\test\query_test.dart --plain-name "queryUnnamed at Sign @ placeholder" --chain-stack-traces -j 1
void main() {
  var con = CoreConnection('postgres',
      database: 'sistemas',
      host: 'localhost',
      port: 5432,
      password: 's1sadm1n',
      textCharset: 'utf8');
  if (Platform.isWindows) {
    con = CoreConnection('dart',
        database: 'sistemas',
        host: 'localhost',
        port: 5435,
        password: 'dart',
        textCharset: 'utf8');
  }

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

    await con.execute('''
        CREATE TABLE "myschema"."test_arrays" ( 
          name NAME,
          varchar_array_type varchar[], 
          int8_array_type int8[],
          int2_array_type int2[],
          names_array_type NAME[]  
        );
        ''');

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
path_type, point_type, polygon_type, text_type, time_type, timestamp_type, timestamptz_type, timetz_type, 
tsquery_type, 
tsvector_type, 
uuid_type, varbit_type, varchar_type, 
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
'(2,3),(4,7)', '(2,3)', '(2,3),(4,7)', 'text example', '19:50', '2022-12-21T15:52:00', '2024-07-23 10:04:55.10298-03', '14:24', 'fat & rat',
'a fat'::tsvector, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',  (X'A'), 'varchar test', 
'<?xml version="1.0"?><book><title>Manual</title><chapter>...</chapter></book>',
'123'::xid, '{"varchar","type",null}', '{1,2,null}', '{true,false,null}', '{"\\336\\255\\276\\357",null}', '{a,b}', '{"2022-12-19"}', '{10.5,1.3}',
array['{"sender":"pablo","body":"us"}']::json[], array['{"sender":"pablo"}']::json[], '{10.50}', '{11.50}', '{"3 days 04:05:06"}', '{"abc"}', '{"19:00"}',
'{"2022-12-21T15:52:00"}', '{"2022-12-21T15:52:00"}', '{"a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"}', '2', '{8,8}', '{2,2}', '{"192.168.100.128/25"}',
'{"192.168.100.128/25"}', array['<?xml version="1.0"?><title>Manual</title>']::xml[], array[(X'A')]::varbit[], 2, '{2,2}'
);''');
  });

  // tearDown(() async {
  //   con.close();
  // });
  group('query', () {
    test('SELECT bit type', () async {
      var res =
          await con.querySimple(r'''SELECT bit_type FROM postgresql_types;''');

      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['1']
      ]);
    });
    test('SELECT bool type', () async {
      var res =
          await con.querySimple(r'''SELECT bool_type FROM postgresql_types;''');

      expect(res.first.first.runtimeType, bool);
      expect(res, [
        [true]
      ]);
    });
    test('SELECT box type', () async {
      var res =
          await con.querySimple(r'''SELECT box_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['(1,1),(0,0)']
      ]);
    });
    test('SELECT bytea type', () async {
      var res = await con
          .querySimple(r'''SELECT bytea_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType.toString(), 'Uint8List');
      //decode('DEADBEEF', 'hex') =>
      // E'\\336\\255\\276\\357'::bytea
      //print(hex.encode([222, 173, 190, 239])); => deadbeef
      expect(res, [
        [
          [222, 173, 190, 239]
        ]
      ]);
    });
    test('SELECT char type', () async {
      var res =
          await con.querySimple(r'''SELECT char_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['A']
      ]);
    });
    test('SELECT cidr type', () async {
      var res =
          await con.querySimple(r'''SELECT cidr_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['192.168.100.128/25']
      ]);
    });
    test('SELECT circle type', () async {
      var res = await con
          .querySimple(r'''SELECT circle_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['<(1,1),2>']
      ]);
    });
    test('SELECT date type', () async {
      var res =
          await con.querySimple(r'''SELECT date_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, DateTime);
      expect(res, [
        [DateTime.parse('2022-12-19 00:00:00.000Z')]
      ]);
    });
    test('SELECT decimal/numeric type', () async {
      var res = await con.querySimple(
          r'''SELECT decimal_numeric_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, double);
      expect(res, [
        [5]
      ]);
    });
    test('SELECT float4 type', () async {
      var res = await con
          .querySimple(r'''SELECT float4_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, double);
      expect(res, [
        [2.3]
      ]);
    });
    test('SELECT float8 type', () async {
      var res = await con
          .querySimple(r'''SELECT float8_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, double);
      expect(res, [
        [500.5]
      ]);
    });
    test('SELECT inet type', () async {
      var res =
          await con.querySimple(r'''SELECT inet_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['192.168.0.0/24']
      ]);
    });
    test('SELECT int2 type', () async {
      var res =
          await con.querySimple(r'''SELECT int2_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, int);
      expect(res, [
        [2]
      ]);
    });
    test('SELECT int4 type', () async {
      var res =
          await con.querySimple(r'''SELECT int4_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, int);
      expect(res, [
        [4]
      ]);
    });
    test('SELECT int8 type', () async {
      var res =
          await con.querySimple(r'''SELECT int8_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, int);
      expect(res, [
        [8]
      ]);
    });
    test('SELECT interval type', () async {
      var res = await con
          .querySimple(r'''SELECT interval_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['3 days 04:05:06']
      ]);
    });
    test('SELECT json type', () async {
      var res =
          await con.querySimple(r'''SELECT json_type FROM postgresql_types;''');
      expect(res.first.first is Map, true);
      expect(res, [
        [
          {"key": "value"}
        ]
      ]);
    });
    test('SELECT jsonb type', () async {
      var res = await con
          .querySimple(r'''SELECT jsonb_type FROM postgresql_types;''');
      expect(res.first.first is Map, true);
      expect(res, [
        [
          {"key": "value"}
        ]
      ]);
    });
    test('SELECT line type', () async {
      var res =
          await con.querySimple(r'''SELECT line_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['{2,-1,-1}']
      ]);
    });
    test('SELECT lseg type', () async {
      var res =
          await con.querySimple(r'''SELECT lseg_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['[(2,3),(4,7)]']
      ]);
    });
    test('SELECT macaddr type', () async {
      var res = await con
          .querySimple(r'''SELECT macaddr_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res, [
        ['08:00:2b:01:02:03']
      ]);
    });
    test('SELECT money type', () async {
      var res = await con
          .querySimple(r'''SELECT money_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first.toString().contains('25'), true);
    });
    test('SELECT path type', () async {
      var res =
          await con.querySimple(r'''SELECT path_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, '((2,3),(4,7))');
    });
    test('SELECT point type', () async {
      var res = await con
          .querySimple(r'''SELECT point_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, '(2,3)');
    });
    test('SELECT polygon type', () async {
      var res = await con
          .querySimple(r'''SELECT polygon_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, '((2,3),(4,7))');
    });
    test('SELECT text type', () async {
      var res =
          await con.querySimple(r'''SELECT text_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, 'text example');
    });
    test('SELECT time type', () async {
      var res =
          await con.querySimple(r'''SELECT time_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, '19:50:00');
    });
    test('SELECT timestamp type', () async {
      var res = await con
          .querySimple(r'''SELECT timestamp_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, DateTime);
      expect(res.first.first, DateTime.parse('2022-12-21 15:52:00.000Z'));
    });
    test('test SELECT timestamptz type', () async {
      var res = await con
          .querySimple(r'''SELECT timestamptz_type FROM postgresql_types;''');
      //print('res ${res.first.first} | ${DateTime.parse('2024-07-23 10:04:55.10298-03')}');
      expect(res.first.first.runtimeType, DateTime); //DateTime
      expect(res.first.first, DateTime.parse('2024-07-23 10:04:55.10298-03'));
    });
    // test('test SELECT timetz type', () async {
    //   var res = await con
    //       .querySimple(r'''SELECT timetz_type FROM postgresql_types;''');
    //   expect(res.first.first.runtimeType, String);
    //   expect(res.first.first, '14:24:00-03');
    // });
    test('SELECT uuid type', () async {
      var res =
          await con.querySimple(r'''SELECT uuid_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11');
    });
    test('SELECT varbit type', () async {
      var res = await con
          .querySimple(r'''SELECT varbit_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, '1010');
    });
    test('SELECT varchar type', () async {
      var res = await con
          .querySimple(r'''SELECT varchar_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first, 'varchar test');
    });
    test('SELECT xml type', () async {
      var res =
          await con.querySimple(r'''SELECT xml_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, String);
      expect(res.first.first,
          '<book><title>Manual</title><chapter>...</chapter></book>');
    });
    test('SELECT xid type', () async {
      var res =
          await con.querySimple(r'''SELECT xid_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType, int);
      expect(res.first.first, 123);
    });
    test('SELECT varchar array type', () async {
      var res = await con
          .querySimple(r'''SELECT varchar_array_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType.toString(), 'List<String?>');
      expect(res.first.first, ['varchar', 'type', null]);
    });
    test('SELECT int4 array type', () async {
      var res = await con
          .querySimple(r'''SELECT int4_array_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType.toString(), 'List<int?>');
      expect(res.first.first, [1, 2, null]);
    });
    test('SELECT bool array type', () async {
      var res = await con
          .querySimple(r'''SELECT bool_array_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType.toString(), 'List<bool?>');
      expect(res.first.first, [true, false, null]);
    });
    test('SELECT bytea array type', () async {
      var res = await con
          .querySimple(r'''SELECT bytea_array_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType.toString(), 'List<Uint8List?>');
      expect(res.first.first, [
        [222, 173, 190, 239],
        null
      ]);
    });
    test('SELECT char array type', () async {
      var res = await con
          .querySimple(r'''SELECT char_array_type FROM postgresql_types;''');
      expect(res.first.first.runtimeType.toString(), 'List<String?>');
      expect(res.first.first, ['a', 'b']);
    });
    test('Bit String Types', () async {
      await con.execute(
          ''' CREATE TEMPORARY TABLE test_bit (a BIT(3), b BIT VARYING(5)); ''');

      await con.querySimple(
          r'''INSERT INTO test_bit VALUES (B'10'::bit(3), B'101');''');

      var result = await con.querySimple(r'''SELECT * FROM test_bit;''');

      expect(result, [
        ['100', '101']
      ]);
    });

    test('select clear', () async {
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

    test('INSERT with queryUnnamed', () async {
      await con.queryUnnamed(r'''
      INSERT INTO test_arrays
      (name, varchar_array_type,int8_array_type, int2_array_type, names_array_type)
      VALUES 
      ($1, $2, $3, $4, $5);
      ''', [
        'Vagner',
        ["João", '''Isaque Sant'Ana'''],
        [1, 2, 3],
        [1, 2, 3],
        ['name']
      ]);

      var results =
          await con.querySimple(r'''SELECT * FROM test_arrays limit 1;''');
      expect(results, [
        [
          'Vagner',
          ['João', 'Isaque Sant\'Ana'],
          [1, 2, 3],
          [1, 2, 3],
          ['name']
        ]
      ]);
    });

    test('queryUnnamed question mark Placeholder', () async {
      await con.queryUnnamed(
        'INSERT INTO test_arrays (name, varchar_array_type,int8_array_type, int2_array_type, names_array_type) VALUES (?, ?, ?, ?, ?);',
        [
          'Vagner',
          ["João", '''Isaque Sant'Ana'''],
          [1, 2, null],
          [1, null, 3],
          ['name1']
        ],
        placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
      );
      var results =
          await con.querySimple(r'''SELECT * FROM test_arrays limit 1;''');
      expect(results, [
        [
          'Vagner',
          ['João', 'Isaque Sant\'Ana'],
          [1, 2, null],
          [1, null, 3],
          ['name1']
        ]
      ]);
    });

    test('queryUnnamed colon : placeholder', () async {
      await con.queryUnnamed(
        'INSERT INTO test_arrays (name, varchar_array_type) VALUES (:name, :varchars);',
        {
          'name': 'Vagner',
          'varchars': ["João", '''Isaque Sant'Ana''']
        },
        placeholderIdentifier: PlaceholderIdentifier.colon,
      );
      var results = await con.querySimple(
          'SELECT name, varchar_array_type FROM test_arrays limit 1;');
      expect(results, [
        [
          'Vagner',
          ['João', 'Isaque Sant\'Ana']
        ]
      ]);
    });

    test('queryUnnamed at Sign @ placeholder', () async {
      await con.queryUnnamed(
        'INSERT INTO test_arrays (name, varchar_array_type) VALUES (@name, @varchars);',
        {
          'name': 'Vagner',
          'varchars': ["João", '''Isaque Sant'Ana''']
        },
        placeholderIdentifier: PlaceholderIdentifier.atSign,
      );
      var results = await con.querySimple(
          'SELECT name, varchar_array_type FROM test_arrays limit 1;');
      expect(results, [
        [
          'Vagner',
          ['João', 'Isaque Sant\'Ana']
        ]
      ]);
    });

    test('runInTransaction INSERT with prepareStatement', () async {
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

    test(
        'runInTransaction INSERT with prepareStatement and executeStatement inside query',
        () async {
      await con.runInTransaction((ctx) async {
        var query = await ctx.prepareStatement(
            r'''INSERT INTO "myschema"."pessoas_cursos" ("idPessoa", "idCurso","name") VALUES ($1, $2 ,$3)''',
            [10, 3, 'Isaque']);
        await query.executeStatement();
      });
      var result = await con
          .querySimple('select * from "myschema"."pessoas_cursos" limit 1');

      expect(result, [
        [1, 10, 3, 'Isaque']
      ]);
    });

    test('runInTransaction queryUnnamed INSERT with @ placeholder', () async {
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
      var results = await con.querySimple(
          'SELECT name, varchar_array_type FROM test_arrays limit 1;');
      expect(results, [
        [
          'Vagner',
          ['João', 'Isaque Sant\'Ana']
        ]
      ]);
    });

    test('querySimple SELECT/INSERT', () async {
      await con.querySimple('''
      CREATE TEMPORARY TABLE temp_location
      (
          id int4,
          city VARCHAR(80),
          street VARCHAR(80)
      )
      ''');
      final re = await con.querySimple(
          '''INSERT INTO temp_location (id,city,street) VALUES (1,'Rio das Ostras','Amaral Peixoto') returning id;''');
      final id = re.first.first;

      final results = await con
          .querySimple('SELECT * FROM temp_location WHERE id=$id limit 1;');

      expect(results, [
        [1, 'Rio das Ostras', 'Amaral Peixoto']
      ]);
    });

    test('queryUnnamed SELECT/INSERT', () async {
      await con.querySimple('''
      CREATE TEMPORARY TABLE temp_location
      (   id int4,
          city VARCHAR(80),
          street VARCHAR(80)
      )
      ''');
      final re = await con.queryUnnamed(
          r'''INSERT INTO temp_location (id,city,street) VALUES ($1,$2,$3) returning id;''',
          [2, 'São Paulo', 'José das Coves']);
      final id = re.first.first;

      var results = await con.queryUnnamed(
          r'SELECT * FROM temp_location WHERE id=$1 limit 1;', [id]);
      expect(results, [
        [2, 'São Paulo', 'José das Coves']
      ]);
    });

    // test('runInTransaction INSERT with failure', () async {
    //   expect(con.runInTransaction((ctx) async {
    //     var statement = await ctx.prepareStatement(
    //         r'''INSERT INTO "myschema"."pessoas_cursos" ("idPessoa", "idCurso","name2") VALUES ($1, $2 ,$3)''',
    //         [10, 3, 'Isaque']);
    //     await ctx.executeStatement(statement);
    //   }), throwsA(isA<PostgresqlException>()));
    // });
  });
}
