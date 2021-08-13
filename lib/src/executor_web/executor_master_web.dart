import 'dart:async';
import 'dart:collection';

import 'package:concurrent_executor/src/concurrent_executor_base.dart';
import 'package:concurrent_executor/src/task/concurrent_task.dart';
import 'package:concurrent_executor/src/task/task_status.dart';
import 'package:logging/logging.dart';

class ExecutorMaster extends Executor {
  static final log = buildLogger();

  static Logger buildLogger() {
    hierarchicalLoggingEnabled = true;
    var log = Logger('Executor_web');
    log.level = Level.INFO;
    log.onRecord.listen((record) {
      print(
          '[${record.level.name}] ${record.time} [Isolate:main] [Logger:${record.loggerName}] -> ${record.message}');
    });
    return log;
  }

  final Queue<TaskWrapper<dynamic>> _tasks = Queue.from([]);

  /// Prevent users from creating manually
  ExecutorMaster.noManually_(int coreWorkerSize /*ignored*/);

  @override
  Future<void> init() async {
    if (status == ExecutorStatus.running) {
      throw StateError('executor has been initialized.');
    } else if (status == ExecutorStatus.closed) {
      throw StateError('executor has been closed.');
    } else if (status == ExecutorStatus.closing) {
      throw StateError('executor is closing.');
    }
    status = ExecutorStatus.running;
  }

  @override
  FutureOr<void> close([CloseLevel level = CloseLevel.immediately]) {
    if (status == ExecutorStatus.created) {
      throw StateError('executor has not initialized.');
    } else if (status == ExecutorStatus.closing) {
      throw StateError('executor is closing.');
    } else if (status == ExecutorStatus.closed) {
      throw StateError('executor has been closed.');
    }
    status = ExecutorStatus.closed;
  }

  @override
  Future<R> submit<R>(ConcurrentTask<FutureOr<R>> task) {
    if (status == ExecutorStatus.closed) {
      throw StateError('executor has been closed.');
    }

    if (_tasks.any((taskWrapper) => taskWrapper.task == task)) {
      log.warning(
          'the task is already in the queue to be executed on the executor');
    }

    var completer = Completer<R>();
    var taskWrapper = TaskWrapper(task, completer);
    _tasks.addLast(taskWrapper);
    taskWrapper.status = TaskStatus.ready;
    Future.microtask(() async {
      try {
        var result = task.run();
        // In order to be consistent with executor_io
        if (result is Future<dynamic>) {
          result = await result;
        }
        taskWrapper.status = TaskStatus.success;
        taskWrapper.completer.complete(result);
        _tasks.remove(taskWrapper);
      } catch (e, s) {
        taskWrapper.status = TaskStatus.error;
        taskWrapper.completer.completeError(e, s);
        _tasks.remove(taskWrapper);
      }
    });
    return completer.future;
  }
}
