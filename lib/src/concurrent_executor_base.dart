import 'dart:async';

import 'package:concurrent_executor/src/executor_web/executor_master_web.dart'
    if (dart.library.io) 'package:concurrent_executor/src/executor_io/executor_master_io.dart';
import 'package:concurrent_executor/src/task/concurrent_task.dart';
import 'package:meta/meta.dart';

abstract class Executor {
  @protected
  Future<void> init();

  /// need user close executor manually
  FutureOr<void> close();

  /// create an executor instance, coreWorkerSize is the number of isolates executing the task
  static Future<Executor> createExecutor([int coreWorkerSize = 1]) async {
    var executor = ExecutorMaster.noManually_(coreWorkerSize);
    await executor.init();
    return executor;
  }

  /// submit a concurrent task, you need to implements ConcurrentTask<R> for your task
  Future<R> submit<R>(ConcurrentTask<FutureOr<R>> task);
}
