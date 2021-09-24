import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:concurrent_executor/src/message.dart';
import 'package:concurrent_executor/src/task/concurrent_task.dart';
import 'package:logging/logging.dart';

class ExecutorWorker {
  /// such as worker not initialized, or already closed
  bool available = false;

  /// whether the worker is currently idle
  bool idle = true;

  final String debugName;

  /// The master isolate sends message to the worker through this sendPort
  late SendPort sendPort;

  ExecutorWorker(this.debugName);

  FutureOr<void> init(SendPort masterSendPort, Stream bstream) async {
    await Isolate.spawn(_IsolateWorker._workerHandler, masterSendPort,
        debugName: debugName);
    await for (var msg in bstream) {
      if (msg is SendPort) {
        sendPort = msg;
        available = true;
        break;
      }
    }
  }

  /// ignore close level, controlled by executor master
  FutureOr<void> close(
      /* [CloseLevel level = CloseLevel.afterRunningFinished] */) {
    available = false;
    sendPort.send(CloseMessage()..level = CloseLevel.immediately);
    return null;
  }

  @override
  String toString() {
    return 'debugName:$debugName, idle:$idle, available:$available';
  }
}

class _IsolateWorker {
  static final Logger _log = buildLogger();

  static Logger buildLogger() {
    hierarchicalLoggingEnabled = true;
    var log = Logger('IsolateWorker');
    log.level = Level.INFO;
    log.onRecord.listen((record) {
      print(
          '[${record.level.name}] ${record.time} [Isolate:${Isolate.current.debugName}] [Logger:${record.loggerName}] -> ${record.message}');
    });
    return log;
  }

  static var _avaiable = true;

  static var _taskWaiter = Completer<List<TaskWrapperBase<dynamic>>>();

  static late final ReceivePort _receivePort;

  static late final _tasks = Queue<TaskWrapperBase<dynamic>>.from([]);

  static void _workerHandler(SendPort masterSendPort) async {
    var currentDebugName = Isolate.current.debugName as String;
    _receivePort = ReceivePort(currentDebugName);
    masterSendPort.send(_receivePort.sendPort);
    _receivePort.listen(_messageProcessor);
    // after all core worker inited, and executor inited, then startup event loop.
    await _taskWaiter.future;
    _taskWaiter = Completer<List<TaskWrapperBase<dynamic>>>();

    // when worker inited, inner tasks is always empty, so just wait for submit task from master.
    var taskList = await _taskWaiter.future;
    _taskWaiter = Completer<List<TaskWrapperBase<dynamic>>>();
    _tasks.addAll(taskList);
    while (_avaiable) {
      if (_tasks.isNotEmpty) {
        var taskWrapper = _tasks.removeFirst();
        try {
          var result = taskWrapper.task.run();
          if (result is Future<dynamic>) {
            result = await result;
          }
          masterSendPort.send(
              WorkerMessage(MessageType.success, currentDebugName)
                ..state = SuccessMessageState(taskWrapper.taskId, result));
        } catch (e, s) {
          /* _log.warning('task: ${taskWrapper.taskId} has an exception: $e'); */
          masterSendPort.send(WorkerMessage(MessageType.error, currentDebugName)
            ..state = ErrorMessageState(taskWrapper.taskId, e, s.toString()));
        }
      } else {
        masterSendPort.send(WorkerMessage(MessageType.idle, currentDebugName));
        var taskList = await _taskWaiter.future;
        // reset for next use
        _taskWaiter = Completer<List<TaskWrapperBase<dynamic>>>();
        _tasks.addAll(taskList);
      }
    }
  }

  static void _messageProcessor(dynamic message) {
    if (message is List<TaskWrapperBase<dynamic>>) {
      _taskWaiter.complete(message);
    } else if (message is CloseMessage) {
      // controlled by executor master
      _avaiable = false;
      _receivePort.close();
      _taskWaiter.complete([]);
      Isolate.current.kill(priority: Isolate.immediate);
    } else if (message is StartupMessage) {
      _taskWaiter.complete([]);
    } else {
      _log.warning(
          'unknown message type: ${message.runtimeType}, message: $message');
    }
  }
}
