import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';

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
  //   var re = await transa.executeUnnamed(
  //       r"""INSERT INTO "crud_teste"."pessoas_cursos" ("idPessoa", "idCurso") VALUES ($1, $2) """,
  //       [10, 3]).toList();
  //   print('periodic: $re');
  //   await con.commit(transa);
  // } catch (e) {
  //   print('catch (e) $e');
  //   await con.rollBack(transa);
  // }
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
        r'''INSERT INTO "myschema"."pessoas_cursos" ("idPessoa", "idCurso","name2") VALUES ($1, $2 ,$3)''',
        [10, 3, 'Isaque']);
    //await ctx.executeStatement(statement);
    await statement.executeStatement();
  });
  var result = await con
      .querySimple('select * from "myschema"."pessoas_cursos" limit 1');
  print('result $result');
  // } on PostgresqlException catch (e, s) {
  //   print('main catch ${e} $s');
  // }

  print('periodic1 fim');
  //});

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

  //await con.close();

  //exit(0);
}
