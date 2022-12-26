import 'dart:async';

import 'package:dargres/dargres.dart';

import 'column_description.dart';
import 'row_info.dart';

class QueryState {
  final int value;
  const QueryState(this.value);
  static const QueryState queued = const QueryState(1);
  static const QueryState busy = const QueryState(6);
  static const QueryState streaming = const QueryState(7);
  static const QueryState done = const QueryState(8);
  static const QueryState init = const QueryState(9);
  static const QueryState error = const QueryState(10);

  @override
  String toString() {
    var v = '';
    if (value == 1) v = 'queued';
    if (value == 6) v = 'busy';
    if (value == 7) v = 'streaming';
    if (value == 8) v = 'done';
    if (value == 9) v = 'init';
    if (value == 10) v = 'error';
    return 'QueryState.$v';
  }
}

class QueryType {
  final String value;
  const QueryType(this.value);
  static const QueryType prepareStatement = const QueryType('prepareStatement');
  static const QueryType namedStatement = const QueryType('namedStatement');
  static const QueryType simple = const QueryType('simple');

  @override
  String toString() {
    return 'QueryType.$value';
  }
}

class Query {
  //statement sql string
  final String sql;

  /// for prepared named statement

  int prepareStatementId = 0;
  bool isUnamedStatement = false;

  /// generate unique name for named prepared Statement
  String get statementName => isUnamedStatement == false
      ? '$prepareStatementId'.padLeft(12, '0')
      : ''; //dargres_statement_$prepareStatementId

  QueryState state = QueryState.queued;

  int rowsAffected = 0;

  /// params for prepared querys
  List _params;

  /// oids for prepared querys
  List _oids = [];

  /// se ouver params é uma Prepared query
  //bool get isPrepared => _params != null || _params?.isEmpty == true;

  QueryType queryType = QueryType.simple;

  /// informa que terminaou a execução dos passos de uma prepared query
  bool isPreparedComplete = false;

  List get preparedParams => _params;
  List get oids => _oids;

  /// funções de conversão de tipo para as colunas
  //List<Function> input_funcs = [];
  //List<List> _rows;
  int rowCount = -1;
  int columnCount = 0;

  /// informações das colunas
  List<ColumnDescription> columns;
  //
  PostgresqlException _error = null;
  set error(PostgresqlException e) {
    _error = e;
  }

  PostgresqlException get error => _error;

  StackTrace stackTrace = null;

  TransactionContext _transactionContext;

  set transactionContext(TransactionContext ctx) {
    _transactionContext = ctx;
  }

  Future<List<Row>> executeStatement() {
    return _transactionContext.executeStatement(this);
  }

  StreamController<Row> _controller = StreamController<Row>();
  Stream<Row> get stream => _controller.stream;

  bool get streamIsClosed {
    return _controller.isClosed;
  }

  /// for use internal not call this
  void reInitStream() {
    _controller = StreamController<Row>();
  }

  Query(
    this.sql, {
    List preparedParams,
    this.prepareStatementId = 0,
    List oidsP,
    this.columns,
    //this.input_funcs = const [],
  }) {
    _params = preparedParams;

    if (oidsP != null) {
      _oids = oidsP;
    }

    error = null;
  }

  Query clone() {
    final newQuery = new Query(
      sql,
      columns: columns,
      prepareStatementId: prepareStatementId,
      preparedParams: preparedParams,
      oidsP: oids,
      //input_funcs: this.input_funcs,
    );
    newQuery.queryType = queryType;
    newQuery.columnCount = columnCount;
    newQuery.rowCount = rowCount;
    newQuery.rowsAffected = rowsAffected;
    newQuery.error = error;
    newQuery.isPreparedComplete = isPreparedComplete;
    newQuery.state = state;

    return newQuery;
  }

  void addPreparedParams(List params, [List oidsP]) {
    _params = params;
    if (oidsP != null) {
      _oids = oidsP;
    }
    isPreparedComplete = false;
  }

  void addOids(List oidsP) {
    if (oidsP != null) {
      _oids = oidsP;
    }
  }

  void addRow(List<dynamic> rowData) {
    var row = Row(rowData, columns);
    rowCount++;
    //_rows.add(row);
    _controller.add(row);
  }

  Future<void> close() async {
    await _controller.close();
    state = QueryState.done;
    //print('Query@close');
  }

  void addStreamError(Object err, [StackTrace stackTrace]) {
    _controller.addError(err, stackTrace);
    // stream will be closed once the ready for query message is received.
  }
}
