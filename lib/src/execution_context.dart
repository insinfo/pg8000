import 'package:dargres/dargres.dart';

abstract class ExecutionContext {
  /// execute a sql command e return affected row count
  /// Example: con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;')
  Future<int> execute(String sql, {Duration? timeout}) ;

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  Future<Results> querySimple(String sql, {Duration? timeout}) ;

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  Future<ResultStream> querySimpleAsStream(String sql);

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
      Duration? timeout});

  Future<Results> queryNamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false, Duration? timeout});

  /// prepare statement
  /// [params] parameters can be a list or a map,
  /// if you use placeholderIdentifier is PlaceholderIdentifier.pgDefault or PlaceholderIdentifier.onlyQuestionMark
  /// it has to be a List, if different it has to be a Map
  /// return Query prepared with statementName for execute with (executeStatement) method
  /// Example:
  /// var statement = await prepareStatement('SELECT * FROM table LIMIT $1', [0]);
  /// var result await executeStatement(statement);
  Future<Query> prepareStatement(String sql, dynamic params,
      {bool isUnamedStatement = false,
      PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
    Duration? timeout});

  /// run prepared query with (prepareStatement) method and return List of Row
  Future<Results> executeStatement(Query query, {bool isDeallocate = false, Duration? timeout});

  /// run query prepared with (prepareStatement) method
  Future<ResultStream> executeStatementAsStream(Query query);

  Future<T> runInTransaction<T>(Future<T> operation(TransactionContext ctx), {
    Duration? timeout,
    Duration? timeoutInner,
  });

  Future<CoreConnection> connect({int? delayBeforeConnect, int? delayAfterConnect});
}
