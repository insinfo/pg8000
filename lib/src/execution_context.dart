import 'query.dart';
import 'to_statement.dart';
import 'results.dart';
import 'fast/row_view.dart';

abstract class ExecutionContext {
  /// execute a sql command e return affected row count
  /// Example: con.execute('DROP SCHEMA IF EXISTS myschema CASCADE;')
  Future<int> execute(String sql);

  /// execute a simple query whitout prepared statement
  /// this use a simple Postgresql Protocol
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  Future<Results> querySimple(String sql);

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
      bool isDeallocate = false});

  Future<Results> queryNamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false});

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
          PlaceholderIdentifier.pgDefault});

  /// run prepared query with (prepareStatement) method and return List of Row
  Future<Results> executeStatement(Query query, {bool isDeallocate = false});

  /// run query prepared with (prepareStatement) method
  Future<ResultStream> executeStatementAsStream(Query query);

  /// Executes through the extended protocol and materializes flat maps
  /// directly from DataRow messages, without intermediate [Row] objects.
  /// [params] is a `List` for PostgreSQL `$n` and explicit `?` placeholders,
  /// or a `Map` for `:` and `@` placeholders. Question-mark mode is never
  /// auto-detected; prefer `$n` in SQL that contains JSON `?` operators.
  /// Set [requireBinaryResults] only when every returned OID has a supported
  /// binary decoder. Unsupported result OIDs fail the query and are never
  /// retried automatically.
  Future<List<Map<String, dynamic>>> queryMaps(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  });

  /// Maps each DataRow directly to an entity. The same [RowView] is reused for
  /// every callback and must not escape [mapper]. Parameter styles follow
  /// [queryMaps], as does [requireBinaryResults].
  Future<List<T>> queryTyped<T>(
    String sql,
    T Function(RowView row) mapper, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  });

  /// Consumes rows synchronously using a reused [RowView], without retaining
  /// rows in the driver. Parameter styles and [requireBinaryResults] follow
  /// [queryMaps].
  Future<void> queryEach(
    String sql,
    void Function(RowView row) onRow, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  });

  /// Compatibility result path backed by the per-connection statement cache.
  /// Parameter styles and [requireBinaryResults] follow [queryMaps].
  Future<Results> queryCached(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  });
}
