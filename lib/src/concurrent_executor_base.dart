import 'dart:async';

import 'package:concurrent_executor/src/executor_web/executor_leader_web.dart'
    if (dart.library.io) 'package:concurrent_executor/src/executor_io/executor_leader_io.dart';
import 'package:concurrent_executor/src/message.dart' show CloseLevel;
import 'package:concurrent_executor/src/task/concurrent_task.dart';
import 'package:meta/meta.dart';

abstract class Executor {
  @protected
  ExecutorStatus status = ExecutorStatus.created;

  @protected
  Future<void> init();

  Iterable<ConcurrentTask<dynamic>> get unfinishedTasks;

  /// need user close executor manually
  FutureOr<void> close([CloseLevel level = CloseLevel.afterRunningFinished]);

  /// create an executor instance, coreWorkerSize is the number of isolates executing the task
  static Future<Executor> createExecutor([int coreWorkerSize = 1]) async {
    var executor = ExecutorLeader.noManually_(coreWorkerSize);
    await executor.init();
    return executor;
  }

  /// submit a concurrent task, you need to implements ConcurrentTask<R> for your task
  Future<R> submit<R>(ConcurrentTask<FutureOr<R>> task);
}

enum ExecutorStatus {
  created,
  running,
  closing,
  closed,
}
