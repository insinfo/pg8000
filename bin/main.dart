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
  var com = CoreConnection('sisadmin', database: 'sistemas');
  print(bool_out(''));
  exit(0);
}
