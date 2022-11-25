import 'dart:io';
import 'dart:math';

import 'package:pg8000/src/converters.dart';
import 'package:pg8000/src/core.dart';
import 'package:pg8000/src/utils/utils.dart';

import 'dart:typed_data';

void main(List<String> args) async {
  var com = CoreConnection('postgres',
      database: 'sistemas',
      host: 'localhost',
      port: 5432,
      password: 's1sadm1n');

  await com.connect();

  // var items = com.execute_simple('select * from crud_teste.cursos limit 2');
  // await for (var item in items) {
  //   print(item);
  // }

  var items =
      com.execute_unnamed('select * from crud_teste.pessoas limit \$1', [1]);
  await for (var item in items) {
    print('item: $item | ${item.map((i) => i.runtimeType).toList()}');
  }

  // var query =
  //     await com.prepare_statement('select * from crud_teste.pessoas limit \$1');
  // query.addPreparedParams([1]);
  // print('fim prepare_statement');
  // var items = com.execute_named(query);
  // await for (var item in items) {
  //   print('item: $item | ${item.map((i) => i.runtimeType).toList()}');
  // }
  // print('fim execute_named');

  //await com.close();

  //exit(0);
}
