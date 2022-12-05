import 'dart:async';

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

  @override
  String toString() {
    var v = '';
    if (value == 1) v = 'queued';
    if (value == 6) v = 'busy';
    if (value == 7) v = 'streaming';
    if (value == 8) v = 'done';
    if (value == 9) v = 'init';
    return 'QueryState.$v';
  }
}

class QueryType {
  final String value;
  const QueryType(this.value);
  static const QueryType prepareStatement = const QueryType('prepareStatement');
  static const QueryType unnamedStatement = const QueryType('unnamedStatement');
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
  String statementName;
  int prepareStatementId = 0;

  QueryState state = QueryState.queued;

  int rowsAffected = 0;

  /// params for prepared querys
  List _params;

  /// oids for prepared querys
  List _oids;

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
  dynamic error = null;

  StreamController<Row> _controller = StreamController<Row>();
  Stream<Row> get stream => _controller.stream;

  bool get streamIsClosed {
    return _controller.isClosed;
  }

  void reInitStream() {
    _controller = StreamController<dynamic>();
  }

  Query(
    this.sql, {
    List preparedParamsP,
    this.prepareStatementId = 0,
    List oidsP,
    this.columns,
    //this.input_funcs = const [],
  }) {
    if (preparedParamsP != null) {
      _params = preparedParamsP;
    }

    if (oidsP != null) {
      _oids = oidsP;
    }

    error = null;
  }

  Query clone() {
    var newQuery = new Query(
      this.sql,
      columns: this.columns,
      prepareStatementId: this.prepareStatementId,
      preparedParamsP: this.preparedParams,
      oidsP: this.oids,
      //input_funcs: this.input_funcs,
    );
    newQuery.queryType = this.queryType;
    newQuery.columnCount = this.columnCount;
    newQuery.rowCount = this.rowCount;
    newQuery.rowsAffected = this.rowsAffected;
    newQuery.statementName = this.statementName;
    newQuery.error = this.error;
    newQuery.isPreparedComplete = this.isPreparedComplete;
    newQuery.state = this.state;

    return newQuery;
  }

  void addPreparedParams(List params, [List oids]) {
    _params = params;
    _oids = oids;
    isPreparedComplete = false;
  }

  void addOids(List oids) {
    _oids = oids;
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

  void addError(Object err) {
    error = err;
    _controller.addError(err);
    // stream will be closed once the ready for query message is received.
  }
}
