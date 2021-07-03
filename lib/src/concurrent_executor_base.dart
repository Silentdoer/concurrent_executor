import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

typedef Callable<R> = R Function();

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
  Queue<Callable<dynamic>> tasks = Queue.from([]);

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

  void _workerMessageProcessor(dynamic message) {
    if (message is _Message) {
      // 这个isolate里是发了IsolateSendPort表示肯定是没有task执行了【可以考虑这个free由参数里提供】
      var isolate = isolates[message.workerDebugName] as _Worker;
      // 先只支持empty的请求
      if (message.type == _MessageType.empty) {
        // 由于数据不能跨isolate，因此只能发消息让master来置为free
        isolate.free = true;
      }
      // 判断tasks不为空，后面的是否free其实都可以不判断，没有空也能发task给它【TODO 后续优化】
      if (tasks.isNotEmpty && isolate.free) {
        isolate.sendPort.send([_TaskWrapper(tasks.removeFirst())]);
        isolate.free = false;
        return;
      }
    } else {
      throw ArgumentError('can not send this type message from sub isolate.');
    }
  }

  // 先只能runnable，且不返还Future，task必须是有静态生命周期的
  void execute(Callable<void> task) {
    var availableWorker =
        isolates.values.where((isolate) => isolate.enabled && isolate.free);
    if (availableWorker.isEmpty) {
      tasks.addLast(task);
    } else {
      // 此时存在已经启用且空闲的，用符合条件的第一个即可
      var freeIsolate = availableWorker.first;
      freeIsolate.sendPort.send([_TaskWrapper(task)]);
      freeIsolate.free = false;
    }
  }
}

enum _MessageType {
  // 告诉master自己task空了
  empty,
  // 请求拉取task，可能还没有空，但是快空了
  pull,
}

class _Message {
  _MessageType type;

  String workerDebugName;

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

  _TaskWrapper(this.task);
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
      var taskModel = tasks.removeFirst();
      taskModel.task();
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
