import 'dart:async';
import 'dart:collection';
import 'exceptions.dart';

import 'query.dart';

class TransactionContext {
  final int transactionId;
  // fila de querys a serem executadas nesta transação
  final Queue<Query> sendQueryQueue = Queue<Query>();

  TransactionContext(this.transactionId);

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  Stream<dynamic> executeSimple(String statement) {
    try {
      var query = Query(statement);
      query.state = QueryState.init;
      query.queryType = QueryType.simple;
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
    }
  }

  /// execute a prepared unnamed statement
  /// Example: com.executeUnnamed('select * from crud_teste.pessoas limit \$1', [1]);
  Stream<dynamic> executeUnnamed(String statement, List params,
      [List oids = const []]) {
    try {
      var query = Query(statement);
      query.state = QueryState.init;
      query.queryType = QueryType.unnamedStatement;
      query.addPreparedParams(params, oids);
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return Stream.fromFuture(Future.error(ex, st));
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
