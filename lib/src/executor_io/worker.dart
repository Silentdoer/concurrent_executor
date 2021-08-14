import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:concurrent_executor/concurrent_executor.dart';
import 'package:concurrent_executor/src/message.dart';
import 'package:concurrent_executor/src/task/concurrent_task.dart';
import 'package:logging/logging.dart';

class MasterWorker {
  /// such as worker not initialized, or already closed
  bool available = false;

  /// whether the worker is currently idle
  bool idle = true;

  final String debugName;

  /// The master isolate sends message to the worker through this sendPort
  late SendPort sendPort;

  MasterWorker(this.debugName);

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

  /// TODO， send msg to worker
  FutureOr<bool> close([CloseLevel level = CloseLevel.afterRunningFinished]) {
    switch (level) {
      case CloseLevel.immediately:
        break;
      case CloseLevel.afterRunningFinished:
        break;
      case CloseLevel.afterAllFinished:
        break;
    }

    return true;
  }
}

class _IsolateWorker {
  static Logger log = buildLogger();

  static Logger buildLogger() {
    hierarchicalLoggingEnabled = true;
    var log = Logger('MasterWorker');
    log.level = Level.INFO;
    log.onRecord.listen((record) {
      print(
          '[${record.level.name}] ${record.time} [Isolate:${Isolate.current.debugName}] [Logger:${record.loggerName}] -> ${record.message}');
    });
    return log;
  }

  static void _workerHandler(SendPort masterSendPort) async {
    var tasks = Queue<TaskWrapperBase<dynamic>>.from([]);
    var currentDebugName = Isolate.current.debugName as String;
    var receivePort = ReceivePort(currentDebugName);
    masterSendPort.send(receivePort.sendPort);
    var bstream = receivePort.asBroadcastStream();
    while (true) {
      if (tasks.isNotEmpty) {
        var taskWrapper = tasks.removeFirst();
        try {
          var result = taskWrapper.task.run();
          if (result is Future<dynamic>) {
            result = await result;
          }
          masterSendPort.send(
              WorkerMessage(MessageType.success, currentDebugName)
                ..state = SuccessMessageState(taskWrapper.taskId, result));
        } catch (e, s) {
          /* log.warning('task: ${taskWrapper.taskId} has an exception: $e'); */
          masterSendPort.send(WorkerMessage(MessageType.error, currentDebugName)
            ..state = ErrorMessageState(taskWrapper.taskId, e, s.toString()));
        }
      } else {
        // worker's tasks is empty, pull some from master
        masterSendPort.send(WorkerMessage(MessageType.idle, currentDebugName));
        await for (var message in bstream) {
          if (message is List<TaskWrapperBase<dynamic>>) {
            tasks.addAll(message);
          } else {
            log.warning(
                'unknown message type: ${message.runtimeType}, message: $message');
          }
          break;
        }
      }
    }
  }
}

enum IsolateWorkerStatus {
  created,
  running,
  closing,
  closed,
}