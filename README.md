# pg8000
an attempt to port Tony Locke's pg8000 python library https://github.com/tlocke/pg8000

pg8000 is a pure-Dart PostgreSQL driver

this is still experimental, that said, I believe it already works in several scenarios, but it is not yet well tested, the idea is to have as few dependencies as possible and be very fast, at the moment it only depends on the "crypto" and "convert" package , this code was heavily inspired by other PostgreSQL driver implementations and other related projects like

- [x] https://github.com/tlocke/pg8000
- [x] https://github.com/wulczer/postgres-on-the-wire
- [x] https://github.com/jasync-sql/jasync-sql
- [x] https://github.com/npgsql/npgsql
- [x] https://github.com/tomyeh/postgresql
- [x] https://github.com/isoos/postgresql-dart
- [x] https://github.com/pgjdbc/pgjdbc
- [x] https://github.com/will/crystal-pg
- [x] https://github.com/lib/pq


### Currently supports:

#### Authentication:
    - [x] CleartextPassword
    - [x] MD5Password
    - [x] SASL SCRAM-SHA-256

#### Transaction:
    - [x] PHP PDO style
    - [x] Closure

#### Notices And Notifications:
    - [x] Working

#### Charset supported:
    - [x] latin1
    - [x] utf8
    - [x] ascii

## creating a connection and executing a simple select
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    var result = await con.executeSimple('select 1').toList();
    print('result $result');
    //result [[1]]
    await con.close();

```

## create a connection and execute a PHP PDO style transaction
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
      await transaction.executeSimple(
          """INSERT INTO "people" ("name", "dateRegister") VALUES ('Alex', '2022-11-30 16:22:03') returning id""").toList();
      await con.commit(transaction);
    } catch (e) {
      await con.rollBack(transaction);
    }

    await con.close();

```

## create a connection and perform a transaction in a closure
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
        return ctx.executeSimple(
        """INSERT INTO "people" ("name", "dateRegister") VALUES ('Alex', '2022-11-30 16:22:03') returning id""").toList();
    });

    await con.close();

```

## executing a unnamed prepared statement
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();

    var result = await con.executeUnnamed(
      r"""INSERT INTO "people" ("name", "dateRegister", "id") VALUES ($1, $2, $3) returning id""",
      ['Alex', DateTime(2023, 1, 1), 4]).toList();

    print('result $result');
    //result [[4]]

    await con.close();

```

## executing a named prepared statement
```dart
    var con = CoreConnection(
        'user',
        database: 'dataBaseTest',
        host: 'localhost',
        port: 5432,
        password: '123456',       
    );

    await con.connect();
    var query = await con.prepareStatement(r'select * from people limit $1');
    query.addPreparedParams([1]);   
    var items = await con.executeNamed(query).toList();
    print('result: $items');
    print('sql: ${query.sql}');
    //result: [[1, Alex, 2021-12-31 21:00:00.000]]
    //sql: select * from crud_teste.people limit $1
    // server log:
    //2022-12-12 19:47:22.877 -03 [1956] LOG:  execute pg8000_statement_0: select * from crud_teste.people limit $1
    //2022-12-12 19:47:22.877 -03 [1956] DETAIL:  parameters: $1 = '1'
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