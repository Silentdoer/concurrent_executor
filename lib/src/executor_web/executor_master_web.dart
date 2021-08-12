import 'dart:async';

import 'package:concurrent_executor/src/concurrent_executor_base.dart';
import 'package:concurrent_executor/src/task/concurrent_task.dart';

class ExecutorMaster extends Executor {
  /// Prevent users from creating manually
  ExecutorMaster.noManually_(int coreWorkerSize /*ignored*/);

  @override
  Future<void> init() async {}

  @override
  FutureOr<void> close() {
    // TODO: implement shutdown
    throw UnimplementedError();
  }

  @override
  Future<R> submit<R>(ConcurrentTask<FutureOr<R>> task) {
    // TODO: implement submit
    throw UnimplementedError();
  }

  /* @override
  Future<R> submitWithState<S, R>(
      CallableWithState<S, FutureOr<R>> task, S state) {
    // TODO: implement submitWithState
    throw UnimplementedError();
  } */
}
