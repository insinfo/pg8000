import 'dart:async';
import 'dart:io';

import 'package:dargres/dargres.dart';
import 'package:example_dargres/src/example.dart';

//faz o damp do sali do posgresql 8:
// pg_dumpall -U postgres  -f siamweb.sql
//restaura damp do sali no posgresql 14:
//psql -U postgres -p 5433  -f .\siamweb.sql
void main(List<String> args) async {
  var con = CoreConnection(
    'postgres',
    database: 'siamweb',
    host: 'localhost',
    port: 5433,
    password: 's1sadm1n',
    allowAttemptToReconnect: false,
    textCharset: 'latin1',
    //sslContext: sslContext,
  );

  await con.connect();

  Timer.periodic(Duration(milliseconds: 100), (timer) async {
    var anoExercicio = '2019';
    var numcgm = 0;

    var data = await con.queryUnnamed('''
SELECT
    *
FROM
    administracao.acao limit 10
  
''', []);
    print('obtem acao $data\r\n -------------');
    
  });
  //await con.close();
  //exit(0);
}
