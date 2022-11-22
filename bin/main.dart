import 'dart:io';
import 'dart:math';

import 'package:pg8000/src/converters.dart';
import 'package:pg8000/src/core.dart';
import 'package:pg8000/src/utils/utils.dart';

void main(List<String> args) async {
  // print('A'.codeUnits);
  // print(pack('i', [4]));
  //print(ii_pack(4, 4));
  //print(ii_unpack(ii_pack(4, 4)));
  //print(i_unpack(i_pack(4)));
  var com = CoreConnection('postgres',
      database: 'sistemas',
      host: 'localhost',
      port: 5432,
      password: 's1sadm1n');

  await com.connect();

  await com.execute_simple('select * from crud_teste.cursos limit 1');

  //print(Utils.splitList([12, 24, 0, 50, 47, 0], NULL_BYTE));

  //exit(0);
}
