import 'dart:async';

import 'package:dargres/dargres.dart';

Future<void> example1() async {
  // var sslContext = SslContext.createDefaultContext();

  var con = CoreConnection(
    'usermd5',
    database: 'sistemas',
    host: 'localhost',
    port: 5432,
    password: 's1sadm1n',
    allowAttemptToReconnect: false,
    //sslContext: sslContext,
  );

  await con.connect();
//   await con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;');
//   await con.execute('CREATE SCHEMA IF NOT EXISTS myschema;');
  await con.execute('SET search_path TO myschema;');

//   await con.execute('''
//         CREATE TABLE "myschema"."test_arrays" (
//           name NAME,
//   varchar_array_type varchar[],
//   int8_array_type int8[],
//   int2_array_type int2[],
//   names_array_type NAME[]
// );
//         ''');

//   await con.queryUnnamed(r'''
// INSERT INTO test_arrays
// (name, varchar_array_type,int8_array_type, int2_array_type, names_array_type)
//  VALUES
// ($1, $2, $3, $4, $5);
// ''', [
//     'Vagner',
//     ["João", '''Isaque Sant'Ana'''],
//     [1, 2, null],
//     [1, null, 3],
//     ['name1']
//   ]);

  // var rea = await con.queryUnnamed(
  //   'INSERT INTO test_arrays (name, varchar_array_type,int8_array_type, int2_array_type, names_array_type) VALUES (?, ?, ?, ?, ?);',
  //   [
  //     'Vagner',
  //     ["João", '''Isaque Sant'Ana'''],
  //     [1, 2, null],
  //     [1, null, 3],
  //     ['name1']
  //   ],
  //   placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
  // );
  //print('rowsAffected: ${rea.rowsAffected}');

  //var results = await con.querySimple(r'''SELECT * FROM myschema.test_arrays;''');

  // var query = await con.prepareStatement(
  //     'select * from "table_01" inner join "table_02" on "table_02"."idtb1" in "(10,11)" limit 1',
  //     [],placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark);
  //     print('main.dart fim prepareStatement');
  // var results = await con.executeStatement(query);
  // print('results rowsAffected: ${results}');
  // for (var row in results) {
  //   // var cols = row.map((c) => '$c' + ' ${c.runtimeType}\r\n').join('');
  //   // print("$cols");
  //   print(row.toColumnMap());
  // }

  Timer.periodic(Duration(milliseconds: 2000), (timer) async {
    try {
      var res = await con.queryUnnamed('select * from "temp_location"', []);
      print('Timer.periodic $res');
    } catch (e) {
      print('error $e');
      if ('$e'.contains('57P')) {
        await con.connect();
        await con.execute('SET search_path TO myschema;');
      }
    }
  });

  //await con.close();
  //exit(0);
}
