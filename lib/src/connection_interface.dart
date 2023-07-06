import 'package:dargres/dargres.dart';

abstract class ConnectionInterface extends ExecutionContext {
  Future<CoreConnection> connect({int? delayBeforeConnect});
  Future<TransactionContext> beginTransaction();
  Future<void> rollBack(TransactionContext transaction);
  Future<void> commit(TransactionContext transaction);
  Future<void> close();
  Future<T> runInTransaction<T>(Future<T> operation(TransactionContext ctx));
}
