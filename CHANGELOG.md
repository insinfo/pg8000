## 1.0.0

- Initial version

## 1.0.1

- fix bug on insert with prepared statement and implement queryUnnamed method for execute a prepared unnamed statement

## 2.0.0

- migrated to null safety 

## 2.1.0

- placeholder identifier option implemented in queryUnnamed and prepareStatement methods, 
this makes it possible to use the style similar to PHP PDO in prepared 
queries Example: 
    ``` queryUnnamed('SELECT * FROM book WHERE title = ? AND code = ?',['title',10],placeholderIdentifier: PlaceholderIdentifier.onlyQuestionMark) ```


## 2.2.0

- implemented ResultStream and Results class for return data from queryUnnamed and querySimple

## 2.2.1

- fix bugs on queryUnnamed and prepareStatement


## 2.2.2

- fix bugs on query error and database restart error

## 2.2.3

- Serious bug fix that caused intermittent error when executing prepared statement with selects that return too much data

## 2.2.4

- add 'win1252' Windows CP1250 support to CoreConnection 
- Example: var con = CoreConnection('user', database: 'db', host: 'localhost', port: 5432, password: 'pass', textCharset: 'win1252');

## 3.0.0

-  implemented Connection pool (PostgreSqlPool) with option to automatically reconnect in case of connection drop

```dart
 final settings = ConnectionSettings(
    user: 'user',
    database: 'database',
    host: 'localhost',
    port: 5433,
    password: 'password',
    textCharset: 'latin1',
    applicationName: 'dargres',  
  ); 
  final conn = PostgreSqlPool(2, settings, allowAttemptToReconnect: true);
```

## 3.0.1

- fixes critical bug in version 3.0.0 that caused stack overflow, timeout parameters were removed from query execution methods such as queryNamed, queryUnnamed, querySimple, execute, prepareStatement, executeStatement

## 3.0.2

- fix bug on set application_name to postgresql < 8.2  