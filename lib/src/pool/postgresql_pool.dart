import 'dart:async';

import 'package:dargres/dargres.dart';
import 'package:dargres/src/connection_state.dart';

import 'package:pool/pool.dart';

import '../connection_interface.dart';

/// A [QueryExecutor] that manages a pool of PostgreSQL connections.
class PostgreSqlPool implements ConnectionInterface {
  /// The maximum amount of concurrent connections.
  final int size;
  List<CoreConnection> connections = [];

  /// default query Timeout =  300 seconds
  static const defaultTimeout = const Duration(seconds: 300);

  int _index = 0;
  final Pool _pool;
  final Pool _connMutex = Pool(1);

  /// Allow reconnection attempt if PostgreSQL was restarted
  bool allowAttemptToReconnect = false;

  /// restart if timeout is reached
  bool restartOnTimeout = true;
  Duration timeout;
  ConnectionSettings connectionInfo;

  PostgreSqlPool(this.size, this.connectionInfo,
      {this.allowAttemptToReconnect = false, this.timeout: defaultTimeout})
      : _pool = Pool(size, timeout: timeout) {
    // _pool = Pool(size, timeout: timeout);
    assert(size > 0, 'Connection pool cannot be empty.');
  }

  // void reInit() {
  //   _connMutex = Pool(1);
  //   _pool = Pool(size, timeout: timeout);
  // }

  /// Closes all connections.
  Future close() async {
    //print('PostgreSqlPool@close');
    await _pool.close();
    await _connMutex.close();
    return Future.wait(connections.map((c) => c.close()));
  }

  Future _open() async {
    if (connections.isEmpty) {
      final listCon = await Future.wait(
        List.generate(size, (_) async {
          //  logger?.fine('Spawning connections...');
          final settings = connectionInfo.clone();
          settings.connectionName = 'pool_connection_$_index';
          //print( 'PostgreSqlPool@_open spawning connection: ${settings.connectionName}');
          final executor = CoreConnection.fromSettings(settings);
          await executor.connect();
          return executor;
        }),
      );
      connections.addAll(listCon);
    }
  }

  Future<CoreConnection> _next() {
    //print('PostgreSqlPool@_next');
    return _connMutex.withResource(() async {
      await _open();
      if (_index >= size) _index = 0;
      final currentConnIdx = _index++;
      //print('PostgreSqlExecutorPool currentConnIdx $currentConnIdx ');
      return connections[currentConnIdx];
    });
  }

  /// execute a sql command e return affected row count
  /// Example: con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;')
  Future<int> execute(String sql, {Duration? timeout}) {
    //print('PostgreSqlPool@execute');
    return _pool.withResource(() async {
      final executor = await _next();
      //print(  'PostgreSqlPool@execute connectionState: ${executor.connectionState}');
      if (executor.connectionState == ConnectionState.closed) {
        await executor.tryReconnect();
        return Future.error(
            Exception('PostgreSqlPool@execute trying to reconnect...'));
      }
      if (executor.connectionState == ConnectionState.socketConnecting) {
        return Future.error(Exception('PostgreSqlPool@execute connecting...'));
      }
      if (executor.connectionState == ConnectionState.authenticating) {
        return Future.error(
            Exception('PostgreSqlPool@execute authenticating...'));
      }
      if (timeout != null) {
        return executor.execute(sql).timeout(timeout);
      } else {
        return executor.execute(sql);
      }
    });
  }

  Future<TransactionContext> beginTransaction({Duration? timeout}) {
    //print('PostgreSqlPool@execute');
    // return _pool.withResource(() async {
    //   final executor = await _next();
    //   //print('PostgreSqlPool@execute connectionState: ${executor.connectionState}');
    //   if (executor.connectionState == ConnectionState.closed) {
    //     await executor.tryReconnect();
    //     return Future.error(
    //         Exception('PostgreSqlPool@execute trying to reconnect...'));
    //   }
    //   if (executor.connectionState == ConnectionState.socketConnecting) {
    //     return Future.error(Exception('PostgreSqlPool@execute connecting...'));
    //   }
    //   if (executor.connectionState == ConnectionState.authenticating) {
    //     return Future.error(
    //         Exception('PostgreSqlPool@beginTransaction authenticating...'));
    //   }
    //   final result = await executor.beginTransaction(timeout: timeout);
    //   return result;
    // });
    throw UnimplementedError();
  }

  Future<void> commit(TransactionContext transaction,
      {Duration? timeout}) async {
    //await transaction.connection.commit(transaction, timeout: timeout);
    throw UnimplementedError();
  }

  Future<void> rollBack(TransactionContext transaction,
      {Duration? timeout}) async {
    //await transaction.connection.rollBack(transaction, timeout: timeout);
    throw UnimplementedError();
  }

  /// execute querys in transaction
  /// [timeout]
  /// [timeoutInner] timeout of operation inside Transaction
  Future<T> runInTransaction<T>(
    Future<T> operation(TransactionContext ctx), {
    Duration? timeout,
    Duration? timeoutInner,
  }) async {
    if (timeout == null) {
      timeout = defaultTimeout;
    }
    if (timeoutInner == null) {
      timeoutInner = defaultTimeout;
    }

    // print('runInTransaction timeout $timeout | timeoutInner $timeoutInner');

    // print('PostgreSqlPool@runInTransaction');
    return _pool.withResource(() async {
      final executor = await _next();
      //print( 'PostgreSqlPool@runInTransaction connectionState: ${executor.connectionState}');
      if (executor.connectionState == ConnectionState.closed) {
        await executor.tryReconnect();
        //print('runInTransaction tryReconnect end');
        return Future.error(Exception(
            'PostgreSqlPool@runInTransaction trying to reconnect...'));
      }
      if (executor.connectionState == ConnectionState.socketConnecting) {
        return Future.error(
            Exception('PostgreSqlPool@runInTransaction connecting...'));
      }
      if (executor.connectionState == ConnectionState.authenticating) {
        return Future.error(
            Exception('PostgreSqlPool@runInTransaction authenticating...'));
      }

      var result;
      TransactionContext? transa;
      try {
        if (timeout != null) {
          transa = await executor.beginTransaction().timeout(timeout);
        } else {
          transa = await executor.beginTransaction();
        }

        if (timeoutInner != null) {
          result = await operation(transa).timeout(timeoutInner);
        } else {
          result = await operation(transa);
        }

        if (timeout != null) {
          await executor.commit(transa).timeout(timeout);
        } else {
          await executor.commit(transa);
        }
      } catch (e) {
        if (transa != null) {
          if (timeout != null) {
            await executor.rollBack(transa).timeout(timeout);
          } else {
            await executor.rollBack(transa);
          }
        }
        rethrow;
      }

      return result;
    });
  }

  /// execute a prepared unnamed statement
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example: com.queryUnnamed(r'select * from crud_teste.pessoas limit $1', [1]);
  Future<Results> queryUnnamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false,
      Duration? timeout}) {
    //print('PostgreSqlPool@queryUnnamed');
    return _pool.withResource(() async {
      final executor = await _next();
      if (allowAttemptToReconnect == true) {
        if (executor.connectionState == ConnectionState.closed) {
          await executor.tryReconnect();
          throw Exception('PostgreSqlPool@queryNamed trying to reconnect...');
        }
        if (executor.connectionState == ConnectionState.socketConnecting) {
          throw Exception(
              'PostgreSqlPool@queryNamed connecting...'); //Future.error(
        }
        if (executor.connectionState == ConnectionState.authenticating) {
          throw Exception('PostgreSqlPool@queryNamed authenticating...');
        }
      }

      if (timeout != null) {
        return executor
            .queryUnnamed(
              sql,
              params,
              placeholderIdentifier: placeholderIdentifier,
              isDeallocate: isDeallocate,
            )
            .timeout(timeout);
      } else {
        return executor.queryUnnamed(
          sql,
          params,
          placeholderIdentifier: placeholderIdentifier,
          isDeallocate: isDeallocate,
        );
      }
    });
  }

  /// execute a prepared named statement
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example: com.queryUnnamed(r'select * from crud_teste.pessoas limit $1', [1]);
  Future<Results> queryNamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false,
      Duration? timeout}) {
    return _pool.withResource(() async {
      final executor = await _next();
      if (allowAttemptToReconnect == true) {
        if (executor.connectionState == ConnectionState.closed) {
          await executor.tryReconnect();
          throw Exception('PostgreSqlPool@queryNamed trying to reconnect...');
        }
        if (executor.connectionState == ConnectionState.socketConnecting) {
          throw Exception(
              'PostgreSqlPool@queryNamed connecting...'); //Future.error(
        }
        if (executor.connectionState == ConnectionState.authenticating) {
          throw Exception('PostgreSqlPool@queryNamed authenticating...');
        }
      }

      if (timeout != null) {
        return executor
            .queryNamed(
              sql,
              params,
              placeholderIdentifier: placeholderIdentifier,
              isDeallocate: isDeallocate,
            )
            .timeout(timeout);
      } else {
        return executor.queryNamed(
          sql,
          params,
          placeholderIdentifier: placeholderIdentifier,
          isDeallocate: isDeallocate,
        );
      }
    });
  }

  Future<Results> querySimple(String sql, {Duration? timeout}) async {
    var res = Results([], RowsAffected());

    res = await _pool.withResource<Results>(() async {
      //print('PostgreSqlPool@querySimple executor b');
      final executor = await _next();
      if (allowAttemptToReconnect == true) {
        if (executor.connectionState == ConnectionState.closed) {
          await executor.tryReconnect();
          throw Exception('PostgreSqlPool@querySimple trying to reconnect...');
        }
        if (executor.connectionState == ConnectionState.socketConnecting) {
          throw Exception(
              'PostgreSqlPool@querySimple connecting...'); //Future.error(
        }
        if (executor.connectionState == ConnectionState.authenticating) {
          throw Exception('PostgreSqlPool@querySimple authenticating...');
        }
      }

      // try {
      // result = await executor.querySimple(sql);
      // } catch (e) {
      //   if (allowAttemptToReconnect == true) {
      //FATAL 28000 no pg_hba.conf entry for host
      //if code is 57P01 postgresql restart
      // if (e.toString().contains('57P') || e.toString().contains('28000')) {
      //   //print( 'PostgreSqlPool@querySimple sem conexão ${executor.connectionName}');
      //   await executor.tryReconnect().timeout(timeout);
      // }
      //   }
      //   rethrow;
      // }

      if (timeout != null) {
        return executor.querySimple(sql).timeout(timeout);
      } else {
        return executor.querySimple(sql);
      }
    });

    return res;
  }

  Future<ResultStream> querySimpleAsStream(String sql) {
    // return _pool.withResource(() async {
    //   final executor = await _next();
    //   if (allowAttemptToReconnect == true) {
    //     if (executor.connectionState == ConnectionState.closed) {
    //       await executor.tryReconnect();
    //       throw Exception(
    //           'PostgreSqlPool@querySimpleAsStream trying to reconnect...');
    //     }
    //     if (executor.connectionState == ConnectionState.socketConnecting) {
    //       throw Exception(
    //           'PostgreSqlPool@querySimpleAsStream connecting...'); //Future.error(
    //     }
    //     if (executor.connectionState == ConnectionState.authenticating) {
    //       throw Exception(
    //           'PostgreSqlPool@querySimpleAsStream authenticating...');
    //     }
    //   }
    //   var result;

    //   result = await executor.querySimpleAsStream(sql);
    // } catch (e) {
    //   if (allowAttemptToReconnect == true) {
    //     //FATAL 28000 no pg_hba.conf entry for host
    //     //if code is 57P01 postgresql restart
    //     if (e.toString().contains('57P') || e.toString().contains('28000')) {
    //       //print('PostgreSqlPool@querySimpleAsStream sem conexão ${executor.connectionName}');
    //       await executor.tryReconnect().timeout(timeout);
    //     }
    //   }
    //   rethrow;
    // }
    //return result;
    // });
    throw UnimplementedError();
  }

  /// prepare statement
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example:
  /// var statement = await prepareStatement('SELECT * FROM table LIMIT $1', [0]);
  /// var result await executeStatement(statement);
  Future<Query> prepareStatement(
    String sql,
    dynamic params, {
    bool isUnamedStatement = false,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    Duration? timeout,
  }) {
    return _pool.withResource(() async {
      final executor = await _next();
      if (allowAttemptToReconnect == true) {
        if (executor.connectionState == ConnectionState.closed) {
          await executor.tryReconnect();
          throw Exception(
              'PostgreSqlPool@querySimpleAsStream trying to reconnect...');
        }
        if (executor.connectionState == ConnectionState.socketConnecting) {
          throw Exception(
              'PostgreSqlPool@querySimpleAsStream connecting...'); //Future.error(
        }
        if (executor.connectionState == ConnectionState.authenticating) {
          throw Exception(
              'PostgreSqlPool@querySimpleAsStream authenticating...');
        }
      }

      //try {
      // result = await executor.prepareStatement(sql, params,
      //     isUnamedStatement: isUnamedStatement,
      //     placeholderIdentifier: placeholderIdentifier);
      // } catch (e) {
      //   if (allowAttemptToReconnect == true) {
      //     //FATAL 28000 no pg_hba.conf entry for host
      //     //if code is 57P01 postgresql restart
      //     if (e.toString().contains('57P') || e.toString().contains('28000')) {
      //       //print( 'PostgreSqlPool@prepareStatement sem conexão ${executor.connectionName}');
      //       await executor.tryReconnect().timeout(timeout!);
      //     }
      //   }
      //   rethrow;
      // }
      if (timeout != null) {
        return executor
            .prepareStatement(sql, params,
                isUnamedStatement: isUnamedStatement,
                placeholderIdentifier: placeholderIdentifier)
            .timeout(timeout);
      } else {
        return executor.prepareStatement(sql, params,
            isUnamedStatement: isUnamedStatement,
            placeholderIdentifier: placeholderIdentifier);
      }
    });
  }

  /// run prepared query with (prepareStatement) method and return List of Row
  Future<Results> executeStatement(
    Query query, {
    bool isDeallocate = false,
    Duration? timeout,
  }) async {
    if (timeout != null) {
      return query
          .executeStatement(isDeallocate: isDeallocate)
          .timeout(timeout);
    } else {
      return query.executeStatement(isDeallocate: isDeallocate);
    }
  }

  Future<ResultStream> executeStatementAsStream(Query query) {
    throw UnimplementedError();
  }

  @override
  Future<CoreConnection> connect({int? delayBeforeConnect}) {
    throw UnimplementedError();
  }
}
