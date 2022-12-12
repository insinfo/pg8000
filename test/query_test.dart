import 'package:pg8000/src/core.dart';

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

    test('test select clear from ', () async {
      try {
        await con.execute('INSERT INTO t99 VALUES (1, 2, 3)');
      } catch (e) {
        //
      }
      var res = await con.executeSimple('select * from t1').toList();
      expect(res, []);
    });
  });
}
