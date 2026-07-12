import 'dart:async';
import 'dart:typed_data';

import 'column_description.dart';
import 'core.dart';
import 'exceptions.dart';
import 'fast/result_schema.dart';
import 'results.dart';
import 'row_info.dart';
import 'to_statement.dart';
import 'transaction_context.dart';

/// Receives a complete PostgreSQL DataRow body directly from the socket
/// buffer. [offset] and [length] delimit the body inside [bytes].
typedef DataRowSink = void Function(Uint8List bytes, int offset, int length);

class QueryType {
  final String value;
  const QueryType(this.value);
  static const QueryType prepareStatement = QueryType('prepareStatement');
  static const QueryType execStatement = QueryType('execStatement');
  static const QueryType extended = QueryType('extended');
  static const QueryType simple = QueryType('simple');

  @override
  String toString() {
    return 'QueryType.$value';
  }
}

class Query {
  late String _sql;

  String get getSql => _sql;

  int prepareStatementId = 0;
  bool isUnamedStatement = false;

  /// Encoded protocol identifiers cached per prepared statement.
  Uint8List? encodedStatementName;
  Uint8List? encodedSql;

  CoreConnection? connection;

  Future<Results> executeStatement({bool isDeallocate = false}) {
    if (transactionContext != null) {
      return transactionContext!
          .executeStatement(this, isDeallocate: isDeallocate);
    } else if (connection != null) {
      return connection!.executeStatement(this, isDeallocate: isDeallocate);
    } else {
      throw PostgresqlException(
          'no connection or transactionContext for execute statement');
    }
  }

  /// Generates a unique name for a named prepared statement.
  String get statementName {
    return isUnamedStatement == false
        ? 'dargres_stmt_${'$prepareStatementId'.padLeft(8, '0')}'
        : '';
  }

  RowsAffected rowsAffected = RowsAffected();

  List? _params;

  List _oids = [];

  QueryType queryType = QueryType.simple;

  bool parseComplete = false;

  List get preparedParams => _params ?? const <dynamic>[];
  List get oids => _oids;

  int rowCount = 0;
  int columnCount = 0;

  List<ColumnDescription>? columns;

  /// Schema and pre-resolved decoders used by the DataRow hot path.
  ResultSchema? resultSchema;

  /// Optional direct result sink. When set, no [Row] or stream event is
  /// created for a DataRow.
  DataRowSink? dataRowSink;

  /// Whether this execution requires every result column in binary format.
  ///
  /// This is execution state rather than statement identity: callers may use
  /// the same cached statement in strict-binary and mixed-format modes.
  final bool requireBinaryResults;

  Object? clientError;
  StackTrace? clientStackTrace;

  Completer<void>? _completion;

  /// Completion used by the direct map/typed/callback result paths.
  Future<void> get completed {
    return (_completion ??= Completer<void>()).future;
  }

  bool get hasDirectSink => dataRowSink != null;
  bool get hasCompletionListener => _completion != null;
  PostgresqlException? error;

  StackTrace? stackTrace;

  TransactionContext? transactionContext;

  void resetForRetry() {
    error = null;
    clientError = null;
    clientStackTrace = null;
    stackTrace = null;
    rowsAffected.value = 0;
    rowCount = 0;
  }

  StreamController<Row>? _controller;
  Future<void>? _closeFuture;

  ResultStream get stream =>
      (_controller ??= StreamController<Row>()).asResultStream(rowsAffected);

  bool get streamIsClosed {
    return _controller?.isClosed ?? false;
  }

  final PlaceholderIdentifier placeholderIdentifier;

  void _formatSql(dynamic params) {
    var parameters = params;

    if (placeholderIdentifier == PlaceholderIdentifier.onlyQuestionMark) {
      if (params is! List) {
        throw ArgumentError.value(
            params, 'params', 'Question-mark placeholders require a List.');
      }
      _sql = toStatement2(_sql);
    } else if (placeholderIdentifier == PlaceholderIdentifier.pgDefault) {
      if (params is! List) {
        throw ArgumentError.value(
            params, 'params', 'PostgreSQL placeholders require a List.');
      }
    } else if (placeholderIdentifier != PlaceholderIdentifier.pgDefault) {
      if (params is! Map) {
        throw PostgresqlException(
            'the [params] argument must be a `Map` when using placeholderIdentifier != pgDefault | onlyQuestionMark ');
      }
      final result = toStatement(_sql, params,
          placeholderIdentifier: placeholderIdentifier.value);
      _sql = result[0];
      parameters = result[1];
    }

    _params = parameters;
  }

  Query(String sql,
      {dynamic params,
      this.prepareStatementId = 0,
      List? oidsP,
      this.columns,
      this.connection,
      this.requireBinaryResults = false,
      this.placeholderIdentifier = PlaceholderIdentifier.pgDefault}) {
    if (sql == '') {
      throw PostgresqlException('SQL query is null or empty.');
    }

    if (sql.contains('\u0000')) {
      throw PostgresqlException('Sql query contains a null character.');
    }
    _sql = sql;
    if (params != null) {
      _formatSql(params);
    }

    if (oidsP != null) {
      _oids = oidsP;
    }

    error = null;
  }

  /// Creates independent execution state for a prepared statement. The
  /// statement metadata is shared, while controller, counters and errors are
  /// not, so cached statements can safely serve queued concurrent calls.
  Query execution(dynamic params, {bool? requireBinaryResults}) {
    final newQuery = Query(_sql,
        params: params,
        columns: columns,
        prepareStatementId: prepareStatementId,
        oidsP: oids,
        connection: connection,
        requireBinaryResults:
            requireBinaryResults ?? this.requireBinaryResults);
    newQuery.isUnamedStatement = isUnamedStatement;
    newQuery.queryType = QueryType.execStatement;
    newQuery.columnCount = columnCount;
    newQuery.resultSchema = resultSchema;
    newQuery.parseComplete = true;
    newQuery.transactionContext = transactionContext;
    newQuery.encodedStatementName = encodedStatementName;
    newQuery.encodedSql = encodedSql;
    return newQuery;
  }

  /// Copies only immutable server-side statement metadata. Execution params,
  /// errors, rows and controllers are intentionally not retained by caches.
  Query statementTemplate({ResultSchema? schema}) {
    final template = Query(_sql,
        columns: schema?.columns ?? columns,
        prepareStatementId: prepareStatementId,
        oidsP: oids,
        connection: connection,
        requireBinaryResults: requireBinaryResults);
    template.isUnamedStatement = isUnamedStatement;
    template.queryType = QueryType.prepareStatement;
    template.columnCount = schema?.columnCount ?? columnCount;
    template.resultSchema = schema ?? resultSchema;
    template.parseComplete = true;
    template.encodedStatementName = encodedStatementName;
    template.encodedSql = encodedSql;
    return template;
  }

  void addRow(List<Object?> rowData) {
    var row = Row(rowData, columns!, resultSchema?.nameToIndex);
    rowCount++;
    (_controller ??= StreamController<Row>()).add(row);
  }

  void finish() {
    final completion = _completion;
    if (completion != null && !completion.isCompleted) {
      final err = clientError ?? error;
      if (err == null) {
        completion.complete();
      } else {
        completion.completeError(err, clientStackTrace ?? stackTrace);
      }
    }
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      _closeFuture = controller.close();
    }
  }

  Future<void> close() {
    finish();
    return _closeFuture ?? Future<void>.value();
  }

  void addStreamError(Object err, [StackTrace? stackTrace]) {
    (_controller ??= StreamController<Row>()).addError(err, stackTrace);
    // stream will be closed once the ready for query message is received.
  }
}
