import 'dart:async';
import 'dart:collection';

import 'package:dargres/dargres.dart';

class RowsAffected {
  int value = 0;
  RowsAffected();
}

class ResultStream extends StreamView<Row> {
  RowsAffected rowsAffected;
  ResultStream(Stream<Row> stream, this.rowsAffected) : super(stream);

  /// Creates a new single-subscription stream from the future.
  ///
  /// When the future completes, the stream will fire one event, either
  /// data or error, and then close with a done-event.
  factory ResultStream.fromFuture(Future<dynamic> future) {
    //return ResultStream<T>(Stream.fromFuture(future));

    // Use the controller's buffering to fill in the value even before
    // the stream has a listener. For a single value, it's not worth it
    // to wait for a listener before doing the `then` on the future.
    StreamController<dynamic> controller = new StreamController<dynamic>();
    future.then((value) {
      controller.add(value);
      controller.close();
    }, onError: (error, stackTrace) {
      controller.addError(error, stackTrace);
      controller.close();
    });
    //print('ResultStream@fromFuture');
    return controller.asResultStream();
  }
}

extension ResultStreamControllerExtension<T> on StreamController<T> {
  ResultStream asResultStream([RowsAffected? rowsAffected]) {
    //print('ResultStreamController@asResultStream ${rowsAffected?.value}');
    return ResultStream(this.stream as Stream<Row>,
        rowsAffected == null ? RowsAffected() : rowsAffected);
  }
}

extension StreamToResultsExtension on ResultStream {
  Future<Results> toResults() {
    //print('StreamToResults@toResults ${rowsAffected.value}');
    var result = Results([], this.rowsAffected);
    var completer = new Completer<Results>();
    this.listen(
        (data) {
          result.add(data);
        },
        onError: completer.completeError,
        onDone: () {
          completer.complete(result);
        },
        cancelOnError: true);
    return completer.future;
  }
}
/// this is Result set of Rows from database
class Results extends ListBase<Row> {
  final List<Row> rows;
  final RowsAffected rowsAffected;
  Results(this.rows, this.rowsAffected);

  int get length => rows.length;

  @override
  operator [](int index) {
    return rows[index];
  }

  @override
  void add(Row element) {
    rows.add(element);
  }

  @override
  void addAll(Iterable<Row> iterable) {
    rows.addAll(iterable);
  }

  /// return List of Row as Map
  List<Map<String, dynamic>> toMaps() {
    return rows.map((e) => e.toColumnMap()).toList();
  }

  @override
  void operator []=(int index, value) {
    //print('operator [] $index');
    //rows[index] = value;
    //this[this.length++] = element;
    rows[index] = value;
  }

  @override
  set length(int newLength) {
    UnimplementedError();
  }
}
