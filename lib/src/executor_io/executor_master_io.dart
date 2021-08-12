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

class ExecutorMaster extends Executor {
  static final log = buildLogger();

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

  bool _inited = false;

  /// Number of resident isolates, It does not take effect for web
  final int _coreWorkerSize;

  /// executor master isolate message receiver
  late ReceivePort _receivePort;

  /// Prevent users from creating manually
  ExecutorMaster.noManually_(this._coreWorkerSize);

  String get _nextWorkerDebugName => 'executor_worker_${isolateIncrementNum()}';

  // debugName - Isolate worker
  final Map<String, Worker> _workers = {};

  Queue<TaskWrapper<dynamic>> tasks = Queue.from([]);

  @override
  Future<void> init() async {
    if (_inited) {
      throw StateError('executor has been initialized.');
    }
    _receivePort = ReceivePort();
    var bstream = _receivePort.asBroadcastStream();

    // create and initialize all workers, sync
    for (var i = 0; i < _coreWorkerSize; i++) {
      var debugName = _nextWorkerDebugName;
      var worker = Worker(debugName);
      await worker.init(_receivePort.sendPort, bstream);
      _workers[debugName] = worker;
    }
    // all workers are initialized
    bstream.listen(_messageProcessor);
    _inited = true;
  }

  /// process message for master
  void _messageProcessor(dynamic message) {
    if (message is WorkerMessage) {
      if (message.type == MessageType.idle ||
          message.type == MessageType.pull) {
        var worker = _workers[message.workerDebugName] as Worker;
        worker.idle = MessageType.idle == message.type ? true : false;
        // executor has been closed.
        if (!worker.available) {
          log.warning(
              'executor has been closed, but received message ${message.type} from worker ${message.workerDebugName}');
          return;
        }
        if (tasks.where((task) => task.status == TaskStatus.idle).isNotEmpty) {
          // find out first idle taskWrapper
          var taskWrapper =
              tasks.firstWhere((task) => task.status == TaskStatus.idle);
          worker.sendPort.send([taskWrapper.toSend()]);

          taskWrapper.status = TaskStatus.ready;
          worker.idle = false;
        }
      } else if (message.type == MessageType.success) {
        // task finished success
        var state = message.state as CompleteMessageState;
        var taskWrapper =
            tasks.firstWhere((task) => task.taskId == state.taskId);
        taskWrapper.status = TaskStatus.success;
        taskWrapper.completer.complete(state.result);
        tasks.remove(taskWrapper);
      } else if (message.type == MessageType.error) {
        // task finished failure
        var state = message.state as ErrorMessageState;
        var taskWrapper =
            tasks.firstWhere((task) => task.taskId == state.taskId);
        taskWrapper.status = TaskStatus.error;
        taskWrapper.completer.completeError(
            state.error, StackTrace.fromString(state.stackTrace));
        tasks.remove(taskWrapper);
      } else {
        throw ArgumentError('unknown message type ${message.type}');
      }
    }
  }

  @override
  FutureOr<void> close() {
    // TODO: implement shutdown
    _workers.forEach((_, worker) {
      worker.available = false;
      // fixme
      worker.close();
    });
    print('''executor has shutdown, but these tasks 还没有收到完成消息: $tasks''');
    _receivePort.close();
  }

  @override
  Future<R> submit<R>(ConcurrentTask<FutureOr<R>> task) {
    // find out first available and idle worker
    var availableWorker =
        _workers.values.where((worker) => worker.available && worker.idle);
    var completer = Completer<R>();
    var taskWrapper = TaskWrapper(task, completer);
    tasks.addLast(taskWrapper);
    if (availableWorker.isNotEmpty) {
      var idleWorker = availableWorker.first;
      idleWorker.sendPort.send([taskWrapper.toSend()]);
      taskWrapper.status = TaskStatus.ready;
      idleWorker.idle = false;
    }
    return completer.future;
  }
}
