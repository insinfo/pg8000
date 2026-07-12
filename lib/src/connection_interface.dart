import 'core.dart';
import 'execution_context.dart';
import 'transaction_context.dart';

abstract class ConnectionInterface extends ExecutionContext {
  Future<CoreConnection> connect({int? delayBeforeConnect});
  Future<void> ping();
  Future<bool> checkHealth();
  /// Requests cancellation of the command currently executing on PostgreSQL.
  /// Returns false when the connection is idle.
  Future<bool> cancelCurrentQuery();
  Future<TransactionContext> beginTransaction();
  Future<void> rollBack(TransactionContext transaction);
  Future<void> commit(TransactionContext transaction);
  Future<void> close();
  Future<T> runInTransaction<T>(
      Future<T> Function(TransactionContext context) operation);
}
