/*import 'dart:async';


import 'package:dargres/src/pool/postgres_pool.dart';

void main(List<String> args) async {
  final pg = PgPool(
    PgEndpoint(
      host: 'localhost',
      port: 5433,
      database: 'siamweb',
      username: 'sisadmin',
      password: 's1sadm1n',
    ),
    settings: PgPoolSettings()
      ..maxConnectionAge = Duration(hours: 1)
      ..concurrency = 1,
  );

  var querys = [
    'SELECT count(*) FROM public.sw_processo',
    'SELECT count(*) FROM public.sw_andamento',
    'SELECT count(*) FROM public.sw_processo_apensado',
    'SELECT count(*) FROM public.sw_cga',
    'SELECT count(*) FROM public.sw_cgm'
  ];
 // var rand = Random();
  Timer.periodic(Duration(milliseconds: 1500), (timer) async {
    final f = await pg.run((c) async {
      final rs = await c.queryUnnamed(querys[0], []);
      return rs;
    });

    print('main items: ${f}');
  });

  //exit(0);
}
*/