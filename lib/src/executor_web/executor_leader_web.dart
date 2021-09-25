import 'dart:async';
import 'dart:collection';

import 'package:concurrent_executor/src/concurrent_executor_base.dart';
import 'package:concurrent_executor/src/message.dart' show CloseLevel;
import 'package:concurrent_executor/src/task/concurrent_task.dart';
import 'package:concurrent_executor/src/task/task_status.dart';
import 'package:logging/logging.dart';

class ExecutorLeader extends Executor {
  static final _log = buildLogger();

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

  var _closeLevel = CloseLevel.afterRunningFinished;

  Completer<void>? _closeCompleter;

  final Queue<TaskWrapper<dynamic>> _tasks = Queue.from([]);

  /// Prevent users from creating manually
  ExecutorLeader.noManually_(int coreWorkerSize /*ignored*/);

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
  Iterable<ConcurrentTask<dynamic>> get unfinishedTasks =>
      _tasks.map((e) => e.task);

  @override
  FutureOr<void> close([CloseLevel level = CloseLevel.afterRunningFinished]) {
    if (status == ExecutorStatus.created) {
      throw StateError('executor has not initialized.');
    } else if (status == ExecutorStatus.closing) {
      throw StateError('executor is closing.');
    } else if (status == ExecutorStatus.closed) {
      throw StateError('executor has been closed.');
    }
    _closeLevel = level;
    status = ExecutorStatus.closing;
    switch (level) {
      case CloseLevel.immediately:
        status = ExecutorStatus.closed;
        return null;
      case CloseLevel.afterRunningFinished:
        if (_tasks
            .where((element) => element.status == TaskStatus.ready)
            .isEmpty) {
          status = ExecutorStatus.closed;
          return null;
        }
        break;
      case CloseLevel.afterAllFinished:
        if (_tasks.isEmpty) {
          status = ExecutorStatus.closed;
          return null;
        }
        break;
    }
    _closeCompleter = Completer();
    return _closeCompleter!.future;
  }

  @override
  Future<R> submit<R>(ConcurrentTask<FutureOr<R>> task) {
    if (status == ExecutorStatus.closed) {
      throw StateError('executor has been closed.');
    } else if (status == ExecutorStatus.closing) {
      throw StateError('executor is closing.');
    } else if (status == ExecutorStatus.created) {
      throw StateError('executor is not initialized.');
    }

    if (_tasks.any((taskWrapper) => taskWrapper.task == task)) {
      _log.warning(
          'The task already exists in the queue and will be executed multiple times');
    }

    var completer = Completer<R>();
    var taskWrapper = TaskWrapper(task, completer);
    _tasks.addLast(taskWrapper);
    // No task is currently preparing to execute
    if (_tasks.where((element) => element.status == TaskStatus.ready).isEmpty) {
      _readyTask(taskWrapper).whenComplete(() {
        _triggerNextTaskExecution();
      });
    }
    return completer.future;
  }

  void _triggerNextTaskExecution() {
    //assert(status != ExecutorStatus.created);
    if (status != ExecutorStatus.running) {
      if (_closeLevel != CloseLevel.afterAllFinished) {
        status = ExecutorStatus.closed;
        _closeCompleter!.complete(null);
        return;
      } else if (_tasks.isEmpty) {
        // closing and CloseLevel.afterAllFinished, check tasks is empty
        status = ExecutorStatus.closed;
        _closeCompleter!.complete(null);
        return;
      }
    }
    // it can simply to _tasks.isNotEmpty
    if (_tasks
        //.where((element) => element.status == TaskStatus.idle)
        .isNotEmpty) {
      var taskWrapper = _tasks.first;
      //_tasks.firstWhere((element) => element.status == TaskStatus.idle);
      _readyTask(taskWrapper).whenComplete(_triggerNextTaskExecution);
    }
  }

  Future<void> _readyTask(TaskWrapper<dynamic> taskWrapper) {
    taskWrapper.status = TaskStatus.ready;
    return Future.microtask(() async {
      try {
        //assert(status != ExecutorStatus.created);
        if (status != ExecutorStatus.running &&
            _closeLevel == CloseLevel.immediately) {
          return;
        }
        var result = taskWrapper.task.run();
        if (status != ExecutorStatus.running &&
            _closeLevel == CloseLevel.immediately) {
          return;
        }
        // In order to be consistent with executor_io
        if (result is Future<dynamic>) {
          result = await result;
        }
        if (status != ExecutorStatus.running &&
            _closeLevel == CloseLevel.immediately) {
          return;
        }
        taskWrapper.status = TaskStatus.success;
        taskWrapper.completer.complete(result);
        // flag: consider to store to another queue, such as completeTaskQueue, it's LRU
        _tasks.remove(taskWrapper);
      } catch (e, s) {
        if (status != ExecutorStatus.running &&
            _closeLevel == CloseLevel.immediately) {
          return;
        }
        taskWrapper.status = TaskStatus.error;
        taskWrapper.completer.completeError(e, s);
        // flag: consider to store to another queue
        _tasks.remove(taskWrapper);
      }
    });
  }
}
