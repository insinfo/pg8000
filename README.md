# dargres
[![CI](https://github.com/insinfo/pg8000/actions/workflows/dart.yml/badge.svg)](https://github.com/insinfo/pg8000/actions/workflows/dart.yml)
[![Pub Package](https://img.shields.io/pub/v/dargres.svg)](https://pub.dev/packages/dargres)   

an attempt to port Tony Locke's pg8000 python library https://github.com/tlocke/pg8000

Dargres is a pure-Dart PostgreSQL driver

this code was heavily inspired by other PostgreSQL driver implementations and other related projects like

- [x] https://github.com/tlocke/pg8000
- [x] https://github.com/wulczer/postgres-on-the-wire
- [x] https://github.com/jasync-sql/jasync-sql
- [x] https://github.com/npgsql/npgsql
- [x] https://github.com/tomyeh/postgresql
- [x] https://github.com/isoos/postgresql-dart
- [x] https://github.com/pgjdbc/pgjdbc
- [x] https://github.com/will/crystal-pg
- [x] https://github.com/lib/pq

I'm only able to do this implementation thanks to several open source projects, thanks to the entire open source community for creating all these tools.

### Currently supports:

#### Authentication:
- [x] Cleartext Password
- [x] MD5 Password
- [x] SASL SCRAM-SHA-256

#### Connection:
- [x] No SSL
- [x] With SSL

#### Query statement:
- [x] Simple 
- [x] Unnamed prepared statement
- [x] Named prepared statement 

#### Transaction:
- [x] PHP PDO style
- [x] Closure

#### Notices And Notifications:
- [x] Working

#### Charset supported:
- [x] latin1
- [x] utf8
- [x] ascii
- [x] win1252

#### extreme experimental
- [x] Allow reconnection attempt if postgresql was restarted (allowAttemptToReconnect: true)

#### connection pool
```dart
  final settings = ConnectionSettings(
      user: 'username',
      database: 'database_test',
      host: 'localhost',
      port: 5432,
      password: 'password',
      textCharset: 'win1252',
      applicationName: 'dargres');

   /// The maximum amount of concurrent connections.    
  final concurrency = 4;
  /// Allow reconnection attempt if PostgreSQL was restarted
  final allowAttemptToReconnect = true;

  final conn = PostgreSqlPool(concurrency, settings, allowAttemptToReconnect: allowAttemptToReconnect);

  await conn.runInTransaction((ctx) async {
    final items = await ctx.queryNamed(r'SELECT * FROM pg_stat_activity LIMIT $1',[10],timeout: Duration(seconds: 30));
    print('main items: ${items}');      
  });

```

## Creating a connection with SSL and executing a simple select
```dart
    var sslContext = SslContext.createDefaultContext();

    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',    
        sslContext: sslContext,   
    );

    await con.connect();

    var results = await con.querySimple('select 1');
    print('results: $results');
    //results: [[1]]
    await con.close();

```

## Creating a connection and executing a simple select
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    var results = await con.querySimple('select 1');
    print('results: $results');
    //result [[1]]
    await con.close();

```

## Creating a connection and executing queries with the queryUnnamed method (prepared query) and the querySimple method. and also returning a map as a result
```dart
  var sslContext = SslContext.createDefaultContext();

  var con = CoreConnection(
    'username', 
    database: 'dataBaseTest',
    host: 'localhost', 
    port: 5432,
    password: '123456', 
    allowAttemptToReconnect: false,
    sslContext: sslContext,
  );
 
  await con.connect();
  await con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;');
  await con.execute('CREATE SCHEMA IF NOT EXISTS myschema;');
  await con.execute('SET search_path TO myschema;');

  await con.execute('''
        CREATE TABLE "myschema"."test_arrays" ( 
            name NAME,
            varchar_array_type varchar[], 
            int8_array_type int8[],
            int2_array_type int2[],
            names_array_type NAME[]  
        );
        ''');

  await con.queryUnnamed(r'''
INSERT INTO test_arrays
(name, varchar_array_type,int8_array_type, int2_array_type, names_array_type)
 VALUES 
($1, $2, $3, $4, $5);
''', ['Vagner',["João",'''Isaque Sant'Ana'''],[1,2,3],[1,2,3],['name1']]);

  var results = await con.querySimple(r'''SELECT * FROM test_arrays;''');

  for (var row in results) {
    print(row.toColumnMap());
    //Result: {name: Vagner, varchar_array_type: [João, Isaque Sant'Ana], int8_array_type: [1, 2, 3], int2_array_type: [1, 2, 3], names_array_type: [name1]}
  } 

  await con.close();
  exit(0);

```

## Create a connection and execute a PHP PDO style transaction
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    final transaction = await con.beginTransaction();
    try {
      await transaction.querySimple(
          """INSERT INTO "people" ("name", "dateRegister") VALUES ('Alex', '2022-11-30 16:22:03') returning id""");
      await con.commit(transaction);
    } catch (e) {
      await con.rollBack(transaction);
    }

    await con.close();

```

## Create a connection and perform a transaction in a closure
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    await con.runInTransaction((ctx) async {
        return ctx.querySimple(
        """INSERT INTO "people" ("name", "dateRegister") VALUES ('Alex', '2022-11-30 16:22:03') returning id""");
    });

    await con.close();

```

## Executing a prepared statement like PDO
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    var query = await con.prepareStatement(r'select * from people limit $1',[1]); 
    var results = await con.executeStatement(query);

    print('results: $results');
    print('sql: ${query.sql}');

    //result: [[1, Alex, 2021-12-31 21:00:00.000]]
    //sql: select * from crud_teste.people limit $1
    // server log:
    //2022-12-12 19:47:22.877 -03 [1956] LOG:  execute dargres_statement_0: select * from crud_teste.people limit $1
    //2022-12-12 19:47:22.877 -03 [1956] DETAIL:  parameters: $1 = '1'
    await con.close();

```

## Executing a prepared statement with colon placeholder style
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    await ctx.queryUnnamed(
      'INSERT INTO test_arrays (name, varchar_array_type) VALUES (:name, :varchars);',
      {
        'name': 'Vagner',
        'varchars': ["João", '''Isaque Sant'Ana''']
      },
      placeholderIdentifier: PlaceholderIdentifier.colon,
    );
    
    await con.close();

```

## Executing a prepared statement with at sign placeholder style
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    await ctx.queryUnnamed(
      'INSERT INTO test_arrays (name, varchar_array_type) VALUES (@name, @varchars);',
      {
        'name': 'Vagner',
        'varchars': ["João", '''Isaque Sant'Ana''']
      },
      placeholderIdentifier: PlaceholderIdentifier.atSign,
    );
    
    await con.close();

```

## Executing a prepared statement with question mark placeholder style
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    await ctx.queryUnnamed(
      'INSERT INTO test_arrays (name, varchar_array_type) VALUES (?, ?);',
      {
        'name': 'Vagner',
        'varchars': ["João", '''Isaque Sant'Ana''']
      },
      placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark,
    );
    
    await con.close();

```


## Notices And Notifications it is ideal that creates a dedicated connection to listen to database notifications
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    con.notifications.listen((event) async {
        // LISTEN
        print('$event');
        //Result: {backendPid: 9188, channel: db_change_event, payload: This is the payload}
    });
    
    await con.execute('LISTEN "db_change_event"');
    // NOTIFY
    Timer.periodic(Duration(seconds: 2), (t) async {
        await con.execute("NOTIFY db_change_event, 'This is the payload'");
    });

    await con.close();

```