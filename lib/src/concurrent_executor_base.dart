import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

typedef Callable<R> = R Function();

typedef Runnable = void Function();

/// 还可以支持stop方法来停止所有的worker
class Executor {
  late ReceivePort receivePort;

  /// 线程池里核心线程数
  int coreIsolateSize = 1;

  /// 用于生成每个isolate的debugName
  int _isolateDebugNameIndex = 1;

  String get _isolateDebugName => 'executor_worker_${_isolateDebugNameIndex++}';

  Map<String, _Worker> isolates = {};

  // 在dart里list，queue等只有length没有capacity；
  // 这里只能用dynamic，用T的话必须把T声明在Executor上，这相当于是告诉外部Executor只能接收某种返回类型的task，显然不行
  Queue<_TaskWrapper<dynamic>> tasks = Queue.from([]);

  // 先主要用到coreIsolateSize和tasks
  // 创建Executor后必须await先执行init；
  Executor._(this.coreIsolateSize);

  /// 初始化线程池【接下来的优化方向是看init是否用一个单独的master isolate来处理，然后main里的execute都往master isolate发消息】
  static FutureOr<Executor> createExecutor(int coreSize) async {
    var executor = Executor._(coreSize);
    executor.receivePort = ReceivePort();
    var bstream = executor.receivePort.asBroadcastStream();

    // 一次性先创建coreSize个核心线程
    for (var i = 0; i < executor.coreIsolateSize; i++) {
      var debugName = executor._isolateDebugName;
      var isolate = await Isolate.spawn(
          _workerHandler, executor.receivePort.sendPort,
          debugName: debugName);
      await for (var msg in bstream) {
        if (msg is SendPort) {
          executor.isolates[debugName] = _Worker(true, isolate, msg, true);
          break;
        }
      }
    }
    // 等所有worker都初始化完毕后listen
    bstream.listen(executor._workerMessageProcessor);
    return executor;
  }

  void shutdown() {
    isolates.forEach((_, worker) {
      worker.enabled = false;
      worker.isolate.kill();
    });
    print('''executor has shutdown, but these tasks is not executed: $tasks''');
    receivePort.close();
  }

  void _workerMessageProcessor(dynamic message) {
    if (message is _Message) {
      // TODO 这里也可以用_EmptyMessage, _ompleteMessage来实现
      if (message.type == _MessageType.empty) {
        // 这个isolate里是发了IsolateSendPort表示肯定是没有task执行了【可以考虑这个free由参数里提供】
        var worker = isolates[message.workerDebugName] as _Worker;
        // 由于数据不能跨isolate，因此只能发消息让master来置为free
        worker.free = true;
        // 可能此时已经shutdown了
        if (!worker.enabled) {
          return;
        }
        // 判断tasks不为空，后面的是否free其实都可以不判断，没有空也能发task给它【TODO 后续优化】
        if (tasks.isNotEmpty && worker.free) {
          // 找出第一个没有处于就绪状态下的task
          var taskWrapper = tasks.firstWhere((task) => !task.ready);
          if (taskWrapper.task.runtimeType == Runnable) {
            // 返回值是void的不需要等待worker发送complete消息，因此这里直接移除即可；
            tasks.remove(taskWrapper);
          }
          worker.sendPort.send([taskWrapper]);
          taskWrapper.ready = true;
          worker.free = false;
          return;
        }
      } else if (message.type == _MessageType.complete) {
        var state = message.state as _CompleteMessageState;
        var taskWrapper =
            tasks.firstWhere((element) => element.taskId == state.taskId);
        taskWrapper.completer!.complete(state.result);
      } else if (message.type == _MessageType.pull) {
        // ignored
      } else {
        throw ArgumentError('can not send this type message from worker.');
      }
    }
  }

  /// FutureOr<R>是union类型，它既是R也可以是Future<R>类型
  FutureOr<R> submit<R>(Callable<FutureOr<R>> task) {
    var availableWorker =
        isolates.values.where((isolate) => isolate.enabled && isolate.free);
    // 需要思考R是Future类型时怎么办【用FutureOr<R>应该解决了】
    // 不够后续优化可以考虑将返回值是Future（一般方法内部有io等待）的尽量发到同一个worker里，可以进行集中优化（目前都先await）
    _TaskWrapper taskWrapper;
    if (task.runtimeType == Runnable) {
      taskWrapper = _TaskWrapper.justTask(task);
      if (availableWorker.isNotEmpty) {
        // 此时存在已经启用且空闲的，用符合条件的第一个即可
        var freeIsolate = availableWorker.first;
        // 这里只能用组合模式，否则只能多余的发completer给worker【组合模式即将wrapperBase和completer来共同组合成wrapper】
        // 当然，这里也可以通过冗余指针的方式实现，即创建一个baseWrapper对象，但是属性用wrapper的
        freeIsolate.sendPort.send([taskWrapper]);
        freeIsolate.free = false;
      } else {
        tasks.addLast(taskWrapper);
      }
      // flag 我真机智啊
      return null as FutureOr<R>;
    } else {
      var completer = Completer<R>();
      taskWrapper = _TaskWrapper(task, completer);
      taskWrapper.taskId = int.parse(taskWrapper.taskId.toString());
      // 由于isolate执行完毕后需要告诉master，因此没有执行完毕之前都不能从master里清理
      tasks.addLast(taskWrapper);
      if (availableWorker.isNotEmpty) {
        // 此时存在已经启用且空闲的，用符合条件的第一个即可
        var freeIsolate = availableWorker.first;
        var tmp =
            _TaskWrapper.nonCompleter(taskWrapper.task, taskWrapper.taskId);
        freeIsolate.sendPort.send([tmp]);
        freeIsolate.free = false;
      }
      return completer.future;
    }
  }
}

enum _MessageType {
  // 告诉master自己task空了
  empty,
  // 请求拉取task，可能还没有空，但是快空了
  pull,
  complete,
}

class _Message {
  _MessageType type;

  String workerDebugName;

  dynamic state;

  _Message(this.type, this.workerDebugName);
}

/// 用于executor记录isolate的情况
class _Worker {
  bool enabled = false;

  Isolate isolate;

  /// 网Isolate发送业务消息【由于用了receivePort.first后就不能listen了，因此这个放到callback里赋值
  SendPort sendPort;

  /// 是否空闲
  bool free = true;

  _Worker(this.enabled, this.isolate, this.sendPort, this.free);
}

class _TaskWrapper<R> {
  Callable<R> task;

  Completer<R>? completer;

  int? taskId;

  /// 是否已经处于就绪状态【即已经发给了worker将执行】
  bool ready = false;

  static int _taskIdSeed = 1;

  /// 这里taskId不能用task的hashCode，因为多个task的方法对象可能是同一个，因此会重复
  _TaskWrapper(this.task, this.completer) : taskId = _TaskWrapper._taskIdSeed++;

  _TaskWrapper.nonCompleter(this.task, this.taskId);

  _TaskWrapper.justTask(this.task);
}

class _CompleteMessageState {
  int taskId;
  var result;

  _CompleteMessageState(this.taskId, this.result);
}

void _workerHandler(SendPort sendPort) async {
  var tasks = Queue<_TaskWrapper>.from([]);
  var currentDebugName = Isolate.current.debugName as String;
  var receivePort = ReceivePort(currentDebugName);
  // 往master isolate里发送用于和worker通信的sendPort
  sendPort.send(receivePort.sendPort);
  var bstream = receivePort.asBroadcastStream();
  while (true) {
    if (tasks.isNotEmpty) {
      // execute【在一个文件里是可以直接发送函数的，但是用了包不知道为什么就不行了】
      var taskWrapper = tasks.removeFirst();
      if (taskWrapper.task.runtimeType == Runnable) {
        taskWrapper.task();
        continue;
      }
      var result = taskWrapper.task();
      var resReal;
      // 在这里Future是Type而非Class？
      if (result is Future) {
        resReal = await result;
      } else {
        resReal = result;
      }

      // 执行完毕要给master发消息，让master对此task进行complete【在isolate里complete不会在master里生效】
      sendPort.send(_Message(_MessageType.complete, currentDebugName)
        ..state = _CompleteMessageState(taskWrapper.taskId!, resReal));
    } else {
      // tasks里没有task任务了，请求isolate master分配一些，告诉master是哪个worker要task【甚至还可以支持要多少。。】
      sendPort.send(_Message(_MessageType.empty, currentDebugName));
      await for (var listMsg in bstream) {
        tasks.addAll(listMsg);
        break;
      }
    }
  }
}
