import 'dart:async';
import 'dart:collection';

import 'package:dargres/dargres.dart';
import 'package:dargres/src/core.dart';

import 'exceptions.dart';

import 'query.dart';
import 'row_info.dart';
import 'to_statement.dart';

class TransactionContext {
  final int transactionId;
  // fila de querys a serem executadas nesta transação
  final Queue<Query> sendQueryQueue = Queue<Query>();

  final CoreConnection connection;

  TransactionContext(this.transactionId, this.connection);

  /// Execute a sql command e return affected row count
  /// Example: con.execute('select * from crud_teste.pessoas limit 1')
  Future<int> execute(String sql) async {
    try {
      var query = Query(sql);
      query.state = QueryState.init;
      query.queryType = QueryType.simple;
      _enqueueQuery(query);
      await query.stream.toList();
      return query.rowsAffected.value;
    } catch (ex, st) {
      return Future.error(ex, st);
    }
  }

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  Future<Results<Row>> querySimple(String sql) {
    return querySimpleAsStream(sql).toResults();
  }

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  ResultStream<Row> querySimpleAsStream(String sql) {
    try {
      Query query = Query(sql);
      query.state = QueryState.init;
      query.queryType = QueryType.simple;
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return ResultStream.fromFuture(Future.error(ex, st));
    }
  }

  /// execute a prepared unnamed statement
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example: com.queryUnnamed(r'select * from crud_teste.pessoas limit $1', [1]);
  Future<Results<Row>> queryUnnamed(
    String sql,
    dynamic params, {
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
  }) async {
    try {
      var statement = await prepareStatement(sql, params,
          isUnamedStatement: true,
          placeholderIdentifier: placeholderIdentifier);
      return await executeStatement(statement);
    } catch (ex, st) {
      return Future.error(ex, st);
    }
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
  }) async {
    try {
      var parameters = params;
      var statement = sql;

      if (placeholderIdentifier == PlaceholderIdentifier.onlyQuestionMark) {
        statement = toStatement2(sql);
      } else if (placeholderIdentifier != PlaceholderIdentifier.pgDefault) {
        if (!(params is Map)) {
          throw PostgresqlException(
              'the [params] argument must be a `Map` when using placeholderIdentifier != pgDefault | onlyQuestionMark ');
        }
        final result = toStatement(sql, params,
            placeholderIdentifier: placeholderIdentifier.value);
        statement = result[0];
        parameters = result[1];
      }

      var query = Query(statement, preparedParams: parameters);
      query.state = QueryState.init;
      query.transactionContext = this;
      query.error = null;
      query.isUnamedStatement = isUnamedStatement;
      query.prepareStatementId = connection.prepareStatementId;
      connection.prepareStatementId++;
      query.queryType = QueryType.prepareStatement;
      _enqueueQuery(query);
      await query.stream.toList();
      //cria uma copia
      // var newQuery = query.clone();
      // return newQuery;
      return query;
    } catch (ex, st) {
      return Future.error(ex, st);
    }
  }

  /// run Query prepared with (prepareStatement) method and return List of Row
  Future<Results<Row>> executeStatement(Query query) {
    return executeStatementAsStream(query).toResults();
  }

  /// run Query prepared with (prepareStatement) method and return Stream of Row
  ResultStream<Row> executeStatementAsStream(Query query) {
    try {
      //cria uma copia
      var newQuery = query; //query.clone();
      newQuery.error = null;
      newQuery.state = QueryState.init;
      newQuery.reInitStream();
      //print('execute_named ');
      newQuery.queryType = QueryType.namedStatement;
      _enqueueQuery(newQuery);
      return newQuery.stream;
    } catch (ex, st) {
      return ResultStream.fromFuture(Future.error(ex, st));
    }
  }

  /// coloca a query na fila
  void _enqueueQuery(Query query) {
    if (query.sql == '') {
      throw PostgresqlException('SQL query is null or empty.');
    }

    if (query.sql.contains('\u0000')) {
      throw PostgresqlException('Sql query contains a null character.');
    }

    query.state = QueryState.queued;
    sendQueryQueue.addLast(query);
  }
}
