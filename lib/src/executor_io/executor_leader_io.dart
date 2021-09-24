import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:concurrent_executor/src/concurrent_executor_base.dart';
import 'package:concurrent_executor/src/executor_io/worker.dart';
import 'package:concurrent_executor/src/message.dart';
import 'package:concurrent_executor/src/task/concurrent_task.dart';
import 'package:concurrent_executor/src/task/task_status.dart';
import 'package:concurrent_executor/src/utils/id_util.dart';
import 'package:logging/logging.dart';

class ExecutorLeader extends Executor {
  static final _log = buildLogger();

  static Logger buildLogger() {
    hierarchicalLoggingEnabled = true;
    var log = Logger('Executor_io');
    log.level = Level.INFO;
    log.onRecord.listen((record) {
      print(
          '[${record.level.name}] ${record.time} [Isolate:${Isolate.current.debugName}] [Logger:${record.loggerName}] -> ${record.message}');
    });
    return log;
  }

  CloseLevel _closeLevel = CloseLevel.afterRunningFinished;

  Completer<void>? _closeCompleter;

  /// Number of resident isolates, It does not take effect for web
  final int _coreWorkerSize;

  /// executor master isolate message receiver
  late ReceivePort _receivePort;

  /// Prevent users from creating manually
  ExecutorLeader.noManually_(this._coreWorkerSize);

  String get _nextWorkerDebugName => 'executor_worker_${isolateIncrementNum()}';

  // debugName - Isolate worker
  final Map<String, ExecutorWorker> _workers = {};

  final Queue<TaskWrapper<dynamic>> _tasks = Queue.from([]);

  @override
  Future<void> init() async {
    if (status == ExecutorStatus.running) {
      throw StateError('executor has been initialized.');
    } else if (status == ExecutorStatus.closed) {
      throw StateError('executor has been closed.');
    } else if (status == ExecutorStatus.closing) {
      throw StateError('executor is closing.');
    }
    _receivePort = ReceivePort();
    var bstream = _receivePort.asBroadcastStream();

    // create and initialize all workers, sync
    for (var i = 0; i < _coreWorkerSize; i++) {
      var debugName = _nextWorkerDebugName;
      var worker = ExecutorWorker(debugName);
      await worker.init(_receivePort.sendPort, bstream);
      _log.info('$debugName has been initialized.');
      _workers[debugName] = worker;
    }
    // all workers are initialized
    bstream.listen(_messageProcessor);
    _workers.values.forEach((worker) {
      worker.sendPort.send(StartupMessage());
    });
    status = ExecutorStatus.running;
  }

  @override
  Iterable<TaskWrapper<dynamic>> get unfinishedTasks => _tasks;

  /// process message for master
  void _messageProcessor(dynamic message) {
    if (message is WorkerMessage) {
      if (message.type == MessageType.idle) {
        var worker = _workers[message.workerDebugName] as ExecutorWorker;
        worker.idle = true;
        // executor has been closed.
        if (!worker.available) {
          _log.warning(
              'executor has been closed, but received message ${message.type} from worker ${message.workerDebugName}');
          return;
        }
        if (status == ExecutorStatus.closing) {
          if (_closeLevel == CloseLevel.afterRunningFinished) {
            worker.close();
            // all worker finished inner tasks.
            if (!_workers.values.any((w) => w.available) ||
                !_tasks.any(
                    (taskWrapper) => taskWrapper.status == TaskStatus.ready)) {
              //assert (_tasks.where((taskWrapper) => taskWrapper.status == TaskStatus.ready).isEmpty);
              _receivePort.close();
              status = ExecutorStatus.closed;
              _closeCompleter!.complete();
            }
            return;
          } else if (_closeLevel == CloseLevel.afterAllFinished) {
            // all finished task(success, failured) will removed from _tasks
            if (_tasks.isEmpty) {
              _workers.values.forEach((worker) {
                worker.close();
              });
              _receivePort.close();
              status = ExecutorStatus.closed;
              _closeCompleter!.complete();
              return;
            }
          }
        }
        if (_tasks
            .where((task) => task.status == TaskStatus.created)
            .isNotEmpty) {
          // find out first idle taskWrapper
          var taskWrapper =
              _tasks.firstWhere((task) => task.status == TaskStatus.created);
          worker.sendPort.send([taskWrapper.toSend()]);
          taskWrapper.status = TaskStatus.ready;
          worker.idle = false;
        }
      } else if (message.type == MessageType.success) {
        // task finished success
        var state = message.state as SuccessMessageState;
        var taskWrapper =
            _tasks.firstWhere((task) => task.taskId == state.taskId);
        taskWrapper.status = TaskStatus.success;
        taskWrapper.completer.complete(state.result);
        _tasks.remove(taskWrapper);
      } else if (message.type == MessageType.error) {
        // task finished failure
        var state = message.state as ErrorMessageState;
        var taskWrapper =
            _tasks.firstWhere((task) => task.taskId == state.taskId);
        taskWrapper.status = TaskStatus.error;
        taskWrapper.completer.completeError(
            state.error, StackTrace.fromString(state.stackTrace));
        _tasks.remove(taskWrapper);
      } else {
        throw ArgumentError('unknown message type ${message.type}');
      }
    }
  }

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
        _receivePort.close();
        _workers.values.forEach((worker) {
          worker.close();
        });
        return null;
      case CloseLevel.afterRunningFinished:
        if (_tasks
            .where((taskWrapper) => taskWrapper.status == TaskStatus.ready)
            .isEmpty) {
          _workers.values.forEach((worker) {
            worker.close();
          });
          _receivePort.close();
          status = ExecutorStatus.closed;
          return null;
        }
        break;
      case CloseLevel.afterAllFinished:
        // finished tasks will remove from this queue.
        if (_tasks.isEmpty) {
          _workers.values.forEach((worker) {
            worker.close();
          });
          _receivePort.close();
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
          'the task already exists in the queue and will be executed multiple times');
    }
    // find out first available and idle worker
    var availableWorker =
        _workers.values.where((worker) => worker.available && worker.idle);
    var completer = Completer<R>();
    var taskWrapper = TaskWrapper(task, completer);
    _tasks.addLast(taskWrapper);
    if (availableWorker.isNotEmpty) {
      var idleWorker = availableWorker.first;
      idleWorker.sendPort.send([taskWrapper.toSend()]);
      taskWrapper.status = TaskStatus.ready;
      idleWorker.idle = false;
    }
    return completer.future;
  }
}
