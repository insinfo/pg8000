import 'dart:async';



import 'package:dargres/dargres.dart';

void main(List<String> args) async {
  final settings = ConnectionSettings(
      user: 'sisadmin',
      database: 'siamweb',
      host: 'localhost',
      port: 5433,
      password: 's1sadm1n',
      textCharset: 'latin1',
      applicationName: 'dargres');
  //final conn = CoreConnection.fromSettings(settings);
  //await conn.connect();
  final conn = PostgreSqlPool(1, settings, allowAttemptToReconnect: true);

  var querys = [
    'SELECT count(*) FROM public.sw_processo',
    'SELECT count(*) FROM public.sw_andamento',
    'SELECT count(*) FROM public.sw_processo_apensado',
    'SELECT count(*) FROM public.sw_cga',
    'SELECT count(*) FROM public.sw_cgm'
  ];
  //var rand = Random();
  Timer.periodic(Duration(milliseconds: 200), (timer) async {
    try {
     await conn.runInTransaction((ctx) async {
        final items =
            await ctx.queryNamed(querys[0], []);
        print('main items: ${items}');
        //sleep(Duration(milliseconds: 1500));
        // await Future.delayed(Duration(milliseconds: 1500));

        //   //final items = await ctx.queryUnnamed(querys[rand.nextInt(4)], []);
        //   final statement = await ctx.prepareStatement(querys[0], []);
        //   final items = await ctx.executeStatement(statement,isDeallocate:true); //await statement.executeStatement();
        //   print('main items: ${items}');
      });
    } catch (e, s) {
      print('main ${e}\r\n$s');
    }
  });

  // await conn.close();
  //exit(0);
}
