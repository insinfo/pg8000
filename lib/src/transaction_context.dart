import 'dart:async';
import 'dart:collection';
import 'package:dargres/dargres.dart';

class TransactionContext implements ExecutionContext {
  final int transactionId;
  final Queue<Query> sendQueryQueue = Queue<Query>();

  final CoreConnection connection;
  bool _active = true;
  Object? terminalError;

  bool get isActive => _active;

  TransactionContext(this.transactionId, this.connection);

  void markCompleted() {
    _active = false;
  }

  void markFailed(Object error) {
    terminalError = error;
    _active = false;
  }

  void _ensureActive() {
    if (!_active) {
      throw StateError(terminalError == null
          ? 'Transaction $transactionId is already complete.'
          : 'Transaction $transactionId failed: $terminalError');
    }
  }

  /// Executes SQL through the simple-query protocol and returns affected rows.
  /// Example: con.execute('select * from crud_teste.pessoas limit 1')
  @override
  Future<int> execute(String sql) async {
    _ensureActive();
    var query = Query(sql);
    query.queryType = QueryType.simple;
    _enqueueQuery(query);
    await query.stream.toList();
    return query.rowsAffected.value;
  }

  /// Streams a query through PostgreSQL's simple-query protocol.
  /// https://www.postgresql.org/docs/current/protocol-flow.html#id-1.10.6.7.4
  @override
  Future<Results> querySimple(String sql) async {
    var r = await querySimpleAsStream(sql);
    return r.toResults();
  }

  /// Executes a query through PostgreSQL's simple-query protocol.
  @override
  Future<ResultStream> querySimpleAsStream(String sql) async {
    _ensureActive();
    try {
      Query query = Query(sql);
      query.queryType = QueryType.simple;
      _enqueueQuery(query);
      return query.stream;
    } catch (ex, st) {
      return ResultStream.fromFuture(Future.error(ex, st));
    }
  }

  @override
  Future<List<Map<String, dynamic>>> queryMaps(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    _ensureActive();
    final maps = <Map<String, dynamic>>[];
    await connection.executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        maps.add(query.resultSchema!
            .decodeMap(bytes, baseOffset: offset, messageLength: length));
      };
    },
        transaction: this,
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
    return maps;
  }

  @override
  Future<List<T>> queryTyped<T>(
    String sql,
    T Function(RowView row) mapper, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    _ensureActive();
    final entities = <T>[];
    List<Object?>? values;
    RowView? view;
    await connection.executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        final schema = query.resultSchema!;
        values ??=
            List<Object?>.filled(schema.columnCount, null, growable: false);
        schema.decodeRowInto(bytes, values!,
            baseOffset: offset, messageLength: length);
        view ??= RowView(values!, schema.nameToIndex);
        entities.add(mapper(view!));
      };
    },
        transaction: this,
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
    return entities;
  }

  @override
  Future<void> queryEach(
    String sql,
    void Function(RowView row) onRow, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    _ensureActive();
    List<Object?>? values;
    RowView? view;
    await connection.executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        final schema = query.resultSchema!;
        values ??=
            List<Object?>.filled(schema.columnCount, null, growable: false);
        schema.decodeRowInto(bytes, values!,
            baseOffset: offset, messageLength: length);
        view ??= RowView(values!, schema.nameToIndex);
        onRow(view!);
      };
    },
        transaction: this,
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
  }

  @override
  Future<Results> queryCached(
    String sql, {
    dynamic params,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
    bool requireBinaryResults = false,
  }) async {
    _ensureActive();
    final rows = <Row>[];
    final query = await connection.executeDirect(sql, params, (query) {
      query.dataRowSink = (bytes, offset, length) {
        final schema = query.resultSchema!;
        rows.add(Row(
            schema.decodeRow(bytes, baseOffset: offset, messageLength: length),
            schema.columns,
            schema.nameToIndex));
      };
    },
        transaction: this,
        placeholderIdentifier: placeholderIdentifier,
        requireBinaryResults: requireBinaryResults);
    return Results(rows, query.rowsAffected);
  }

  /// Executes an uncached unnamed extended-protocol statement.
  ///
  /// [params] must be a `List` for PostgreSQL or question-mark placeholders
  /// and a `Map` for named placeholders.
  /// Example: com.queryUnnamed(r'select * from crud_teste.pessoas limit $1', [1]);
  @override
  Future<Results> queryUnnamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false}) async {
    _ensureActive();
    return connection.executeDirectResults(sql, params,
        transaction: this,
        placeholderIdentifier: placeholderIdentifier,
        useCache: false);
  }

  @override
  Future<Results> queryNamed(String sql, dynamic params,
      {PlaceholderIdentifier placeholderIdentifier =
          PlaceholderIdentifier.pgDefault,
      bool isDeallocate = false}) async {
    _ensureActive();
    return connection.executeDirectResults(sql, params,
        transaction: this,
        placeholderIdentifier: placeholderIdentifier,
        useCache: !isDeallocate);
  }

  /// Prepares a server-side statement.
  ///
  /// [params] must be a `List` for PostgreSQL or question-mark placeholders
  /// and a `Map` for named placeholders.
  /// Example:
  /// final statement = await prepareStatement('SELECT * FROM table LIMIT $1', [0]);
  /// final result = await executeStatement(statement);
  @override
  Future<Query> prepareStatement(
    String sql,
    dynamic params, {
    bool isUnamedStatement = false,
    PlaceholderIdentifier placeholderIdentifier =
        PlaceholderIdentifier.pgDefault,
  }) async {
    _ensureActive();
    var query = Query(sql,
        params: params, placeholderIdentifier: placeholderIdentifier);
    query.transactionContext = this;
    query.error = null;
    query.isUnamedStatement = isUnamedStatement;
    query.prepareStatementId = connection.prepareStatementId;
    connection.prepareStatementId++;
    query.queryType = QueryType.prepareStatement;
    _enqueueQuery(query);
    await query.stream.toList();
    return query;
  }

  /// Executes a statement created by [prepareStatement].
  @override
  Future<Results> executeStatement(Query query,
      {bool isDeallocate = false}) async {
    var stm = await executeStatementAsStream(query);
    var result = await stm.toResults();
    if (isDeallocate == true) {
      await execute('DEALLOCATE ${query.statementName}');
    }
    return result;
  }

  /// Streams a statement created by [prepareStatement].
  @override
  Future<ResultStream> executeStatementAsStream(Query query) async {
    _ensureActive();
    try {
      final newQuery = query.execution(query.preparedParams);
      _enqueueQuery(newQuery);
      return newQuery.stream;
    } catch (ex, st) {
      return ResultStream.fromFuture(Future.error(ex, st));
    }
  }

  void _enqueueQuery(Query query) {
    _ensureActive();
    sendQueryQueue.addLast(query);
  }
}
