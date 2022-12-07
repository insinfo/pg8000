import 'package:pg8000/src/core.dart';
import 'package:pg8000/src/exceptions.dart';
import 'package:test/test.dart';

void main() {
  setUp(() async {
    //await db.connect();
  });

  group('Connection', () {
    test('test authentication md5 fromUri', () async {
      /*
CREATE DATABASE database_name 
          WITH TABLESPACE tablespace_name TEMPLATE = template0 
          OWNER = database_user ENCODING 'WIN1252' 
         LC_CTYPE = 'Portuguese_Brazil.1252' LC_COLLATE = 'Portuguese_Brazil.1252';
--create database template1 with owner=postgres encoding='UTF-8' lc_collate='en_US.utf8' lc_ctype='en_US.utf8' template template0;
--CREATE DATABASE maia WITH ENCODING 'LATIN1' TEMPLATE template0 LC_COLLATE="C" LC_CTYPE="C";         
          */

      // var db = CoreConnection('postgres2', //sw.suporte usarioscram //postgres
      //     database: 'teste_latin1', //'siamweb', //sistemas teste
      //     host: 'localhost', //localhost
      //     port: 5432,
      //     password: 's1sadm1n', //s1sadm1n
      //     textCharset: 'latin1'
      //     // sslContext: sslContext,
      //     );

      var db = CoreConnection.fromUri(
          'postgres://postgres:s1sadm1n@localhost:5432/sistemas');
      await db.connect();
      var res = await db.execute('select 1');
      expect(res, equals(1));
    });

    test('test authentication failed for non-existent user', () async {
      var db = CoreConnection.fromUri(
          'postgres://postgres2:s1sadm1n@localhost:5432/sistemas');
      expect(db.connect(), throwsA(isA<PostgresqlException>()));
    });

    test('test authentication md5 fromUri ssl', () async {
      var db = CoreConnection.fromUri(
          'postgres://postgres:s1sadm1n@localhost:5432/sistemas?sslmode=require');
      await db.connect();
      var res = await db.execute('select 1');
      expect(res, equals(1));
    });

    test('test authentication scram', () async {
      var con = CoreConnection(
        'usarioscram',
        database: 'sistemas',
        host: 'localhost',
        port: 5432,
        password: 's1sadm1n',
        // sslContext: sslContext,
      );
      await con.connect();
      var res = await con.execute('select 1');
      expect(res, equals(1));
    });
  });
}
