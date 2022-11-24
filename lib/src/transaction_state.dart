/// Describes whether the a connection is participating in a transaction, and
/// if the transaction has failed.
class TransactionState {
  final String _name;
  
  const TransactionState(this._name);

  @override
  String toString() => _name;

  /// Directly after sending a query the transaction state is unknown, as the
  /// query may change the transaction state. Wait until the query is completed
  /// to query the transaction state.
  static const TransactionState unknown = const TransactionState('unknown');
  
  /// The current session has not opened a transaction.
  static const TransactionState none = const TransactionState('none');
  
  /// The current session has an open transaction.
  static const TransactionState begun = const TransactionState('begun');
  
  /// A transaction was opened on the current session, but an error occurred.
  /// In this state all futher commands will be ignored until a rollback is
  /// issued.
  static const TransactionState error = const TransactionState('error');
}