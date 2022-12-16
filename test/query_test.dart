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
    await con.execute("CREATE TEMPORARY TABLE t1 (f1 int primary key, "
        "f2 bigint not null, f3 varchar(50) null) ");
  });

  group('test query', () {
    // test('test database error', () async {
    //   // var res = await con.execute("INSERT INTO t99 VALUES (1, 2, 3)");
    //   expect(con.execute('INSERT INTO t99 VALUES (1, 2, 3)'),
    //       throwsA(isA<PostgresqlException>()));
    // });

    test('test select clear', () async {
      try {
        await con.execute('INSERT INTO t99 VALUES (1, 2, 3)');
      } catch (e) {
        //
      }
      var res = await con.querySimple('select * from t1');
      expect(res, []);
    });
    test('test runInTransaction INSERT', () async {
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

      expect(con.runInTransaction((ctx) async {
        var statement = await ctx.prepareStatement(
            r'''INSERT INTO "myschema"."pessoas_cursos" ("idPessoa", "idCurso","name2") VALUES ($1, $2 ,$3)''',
            [10, 3, 'Isaque']);
        await ctx.executeStatement(statement);
      }), throwsA(isA<PostgresqlException>()));
    });
  });
}
