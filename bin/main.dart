import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pg8000/src/converters.dart';
import 'package:pg8000/src/core.dart';
import 'package:pg8000/src/ssl_context.dart';
import 'package:pg8000/src/utils/utils.dart';

import 'dart:typed_data';

void main(List<String> args) async {
  // user md5 = postgres
  //user scram = usarioscram
  //

  var sslContext = SslContext.createDefaultContext();

  var con = CoreConnection(
    'usarioscram', //usarioscram //postgres
    database: 'sistemas', //sistemas
    host: 'localhost', //localhost
    port: 5432,
    password: 's1sadm1n', //s1sadm1n
    // sslContext: sslContext,
  );

  // var con = CoreConnection(
  //   'sw.suporte', //usarioscram //postgres
  //   database: 'siamweb', //sistemas
  //   host: '10.0.0.25', //localhost
  //   port: 5432,
  //   password: 'suporte', //s1sadm1n
  //   // sslContext: sslContext,
  // );

  await con.connect();
  //observacoes,resumo_assunto
  // var res = await con.executeSimple('''select *
  //     from protocolo.processo_historico
  //     where ano_exercicio=2022 AND cod_processo=590 limit 1''').toList();

  // print('main $res');

  con.notifications.listen((event) async {
    print('$event');
    //var id = jsonDecode(event['payload'])['record']['id'];

    // var dados = await con
    //     .executeSimple('select * from crud_teste.cursos where id =$id')
    //     .toList();
    // print('notification: ${dados[0]}');
  });

  await con.execute('LISTEN "db_change_event"');

  //await con.execute("NOTIFY aliens_landed, 'This is the payload'");

  // Timer.periodic(Duration(milliseconds: 1000), (t) async {
  // final transa = await con.beginTransaction();
  // try {
  //   await transa.executeUnnamed(
  //       r"""INSERT INTO "crud_teste"."pessoas_cursos" ("idPessoa", "idCurso") VALUES ($1, $2) """,
  //       [10, 3]).toList();
  //   await con.commit(transa);
  // } catch (e) {
  //   print('catch (e) $e');
  //   await con.rollBack(transa);
  // }
  // });

  // Timer.periodic(Duration(milliseconds: 2000), (t) async {
  //   final transa = await con.beginTransaction();
  //   try {
  //     await transa.executeSimple(
  //         """INSERT INTO "crud_teste"."pessoas" ("nome", "dataCadastro", "cpf") VALUES ('Alex', '2022-11-30 16:22:03', '171') returning id""").toList();
  //     await con.commit(transa);
  //   } catch (e) {
  //     await con.rollBack(transa);
  //   }
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
  //     await con.prepare_statement('select * from crud_teste.pessoas limit \$1');
  // query.addPreparedParams([1]);
  // print('fim prepare_statement');
  // var items = await con.execute_named(query).toList();
  // print('fim execute_named $items');
  // print('fim execute_named ${query.sql}');

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
