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
    status = ExecutorStatus.running;
  }

  /// process message for master
  void _messageProcessor(dynamic message) {
    if (message is WorkerMessage) {
      if (message.type == MessageType.idle ||
          message.type == MessageType.pull) {
        var worker = _workers[message.workerDebugName] as ExecutorWorker;
        worker.idle = MessageType.idle == message.type ? true : false;
        // executor has been closed.
        if (!worker.available) {
          _log.warning(
              'executor has been closed, but received message ${message.type} from worker ${message.workerDebugName}');
          return;
        }
        if (_tasks.where((task) => task.status == TaskStatus.idle).isNotEmpty) {
          // find out first idle taskWrapper
          var taskWrapper =
              _tasks.firstWhere((task) => task.status == TaskStatus.idle);
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

  /// close提供几种策略
  /// 1.立刻关闭【包括isolate立刻kill不继续执行正在执行的，危险】，输出还未执行的【master和worker】，不接收任何消息
  /// 2.等待worker执行完毕当前的，不接收idle和pull消息，worker idle后自动退出循环和kill自己；所有worker 结束后打印master还有哪些没有执行的；
  /// 3.等待所有的包括master的执行完毕【不接受新的submit】
  ///
  /// 注意，如果submit提交了两个一模一样的对象要warning一下比较好，毕竟state可能造成脏数据
  /// 
  /// TODO 这里的逻辑是，全部由executor来控制是immediately还是afterRunningFinished还是afterAllFinished
  /// 实现方式是通过executor的task状态是idle则说明还没有添加到isolate里执行，ready则是已经添加到isolate待执行；
  /// 因此如果是immediately（三者都不允许submit），则不需要管task的状态，直接发送让isolate立刻停止即可；
  /// 如果是afterRunningFinished，则当ready为空【isolate请求获取task来执行不予理会且发送close】时为closed【触发
  /// 时机就是isolate请求获取task来执行的时机即可】
  /// 如果是afterAllFinished，则等待ready是空，idle也是空的时候即为closed【也是在isolate请求获取task来执行的时候触发，
  /// 不过这里允许给task执行，直到发现没有了idle task的时候发送close；注意最终executor的closed要求判断所有的worker都close了
  /// （available为false）】
  /// //_receivePort.close();
  ///status = ExecutorStatus.closed; 这两个最后记得关闭一下
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
        _workers.values.forEach((worker) {
          worker.available = false;
          worker.close();
        });
        _workers.clear();
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
          'the task is already in the queue to be executed on the executor');
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
