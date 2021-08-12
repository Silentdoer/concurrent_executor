library executor;

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:concurrent_executor/src/executor.dart';
import 'package:concurrent_executor/src/executor_io/worker_wrapper.dart';
import 'package:concurrent_executor/src/basic_component.dart';
import 'package:concurrent_executor/src/utils/generic_util.dart';
import 'package:concurrent_executor/src/utils/id_util.dart';

class ExecutorMaster extends Executor {

  bool _inited = false;

  /// Number of resident isolates, It does not take effect for web
  final int _coreWorkerSize;

  /// executor master isolate message receiver
  late ReceivePort _receivePort;
  
  /// Prevent users from creating manually
  ExecutorMaster.noManually_(this._coreWorkerSize);

  String get _nextWorkerDebugName => 'executor_worker_${isolateIncrementNum()}';

  final Map<String, WorkerWrapper> _workers = {};

  // 在dart里list，queue等只有length没有capacity；
  // 这里只能用dynamic，用T的话必须把T声明在Executor上，这相当于是告诉外部Executor只能接收某种返回类型的task，显然不行
  // dynamic is _TaskWrapper or _TaskWithStateWrapper
  Queue<dynamic> tasks = Queue.from([]);
  
  @override
  Future<void> init() async {
    if (_inited) {
      throw StateError('executor has been initialized.');
    }
    _receivePort = ReceivePort();
    var bstream = _receivePort.asBroadcastStream();

    // 一次性先创建coreSize个核心线程
    for (var i = 0; i < _coreWorkerSize; i++) {
      /* var isolate = await Isolate.spawn(
          _workerHandler, _receivePort.sendPort,
          debugName: debugName); */
      var debugName = _nextWorkerDebugName;
      var worker = WorkerWrapper(debugName);
      await worker.init(_receivePort.sendPort, bstream);
      _workers[debugName] = worker;
      /* await for (var msg in bstream) {
        if (msg is SendPort) {
          worker.endInit(msg);
          break;
        }
      } */
    }
    // 等所有worker都初始化完毕后listen
    bstream.listen(_workerMessageProcessor);
    _inited = true;
  }

  void _workerMessageProcessor(dynamic message) {
    if (message is Message) {
      // TODO 这里也可以用_EmptyMessage, _ompleteMessage来实现
      if (message.type == MessageType.empty) {
        // 这个isolate里是发了IsolateSendPort表示肯定是没有task执行了【可以考虑这个free由参数里提供】
        var worker = _workers[message.workerDebugName] as WorkerWrapper;
        // 由于数据不能跨isolate，因此只能发消息让master来置为free
        worker.idle = true;
        // 可能此时已经shutdown了
        if (!worker.available) {
          return;
        }
        // 判断tasks不为空，后面的是否free其实都可以不判断，没有空也能发task给它【TODO 后续优化】
        if (tasks.isNotEmpty &&
            tasks.where((task) => !task.ready).isNotEmpty &&
            worker.idle) {
          // 找出第一个没有处于就绪状态下的task
          var taskWrapper = tasks.firstWhere((task) => !task.ready);
          if (taskWrapper.isReturnVoid) {
            // 返回值是void的不需要等待worker发送complete消息，因此这里直接移除即可；
            tasks.remove(taskWrapper);
          }
          if (taskWrapper is TaskWithStateWrapper) {
            // FLAG 似乎不能发Completer对象，否则可能有问题
            worker.sendPort.send([taskWrapper.toNonCompleter()]);
          } else {
            // FLAG 似乎不能发Completer对象，否则可能有问题
            worker.sendPort.send([
              TaskWrapper.nonCompleter(taskWrapper.task, taskWrapper.taskId, taskWrapper.isReturnVoid)
            ]);
          }
          
          taskWrapper.ready = true;
          worker.idle = false;
          return;
        }
      } else if (message.type == MessageType.complete) {
        var state = message.state as CompleteMessageState;
        var taskWrapper =
            tasks.firstWhere((element) => element.taskId == state.taskId);
        taskWrapper.completer!.complete(state.result);
        tasks.remove(taskWrapper);
      } else if (message.type == MessageType.pull) {
        // ignored
      } else {
        throw ArgumentError('can not send this type message from worker.');
      }
    }
  }

  @override
  FutureOr<void> shutdown() {
    // TODO: implement shutdown
    //throw UnimplementedError();
    _workers.forEach((_, worker) {
      worker.available = false;
      // fixme
      worker.shutdown();
    });
    print('''executor has shutdown, but these tasks 还没有收到完成消息: $tasks''');
    _receivePort.close();
  }

  @override
  Future<R> submit<R>(Callable<FutureOr<R>> task) {
    var availableWorker =
        _workers.values.where((isolate) => isolate.available && isolate.idle);
    // 需要思考R是Future类型时怎么办【用FutureOr<R>应该解决了】
    // 不够后续优化可以考虑将返回值是Future（一般方法内部有io等待）的尽量发到同一个worker里，可以进行集中优化（目前都先await）
    
      var completer = Completer<R>();
      var taskWrapper = TaskWrapper(task, completer);
      /* if (voidType == R) {
        taskWrapper.isReturnVoid = true;
      } */
      // 由于isolate执行完毕后需要告诉master，因此没有执行完毕之前都不能从master里清理
      tasks.addLast(taskWrapper);
      if (availableWorker.isNotEmpty) {
        // 此时存在已经启用且空闲的，用符合条件的第一个即可
        var idleIsolate = availableWorker.first;
        idleIsolate.sendPort.send(
            [TaskWrapper.nonCompleter(taskWrapper.task, taskWrapper.taskId, taskWrapper.isReturnVoid)]);
        taskWrapper.ready = true;
        idleIsolate.idle = false;
      }
      return completer.future;
    
  }

  /// FutureOr<R>是union类型，它既是R也可以是Future<R>类型
  /// fuck，似乎很难做到state自定义类型。。
  @override
  Future<R> submitWithState<S, R>(CallableWithState<S, FutureOr<R>> task, S state) {
    var availableWorker =
        _workers.values.where((isolate) => isolate.available && isolate.idle);
    
      var completer = Completer<R>();
      var taskWrapper = TaskWithStateWrapper(task, state, completer);
      /* if (voidType == R) {
        taskWrapper.isReturnVoid = true;
      } */
      // 由于isolate执行完毕后需要告诉master，因此没有执行完毕之前都不能从master里清理
      tasks.addLast(taskWrapper);
      if (availableWorker.isNotEmpty) {
        // 此时存在已经启用且空闲的，用符合条件的第一个即可
        var idleIsolate = availableWorker.first;

        idleIsolate.sendPort.send([taskWrapper.toNonCompleter()]);
        taskWrapper.ready = true;
        idleIsolate.idle = false;
      }
      return completer.future;
    
  }
}