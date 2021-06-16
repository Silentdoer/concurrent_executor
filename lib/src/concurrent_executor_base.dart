import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

typedef Runnable = void Function();

class Executor {
  late ReceivePort receivePort;

  /// 线程池里核心线程数
  int coreIsolateSize = 1;

  /// 用于生成每个isolate的debugName
  int _isolateDebugNameIndex = 1;

  String get _isolateDebugName => 'executor_worker_${_isolateDebugNameIndex++}';

  Map<String, ExecutorIsolateModel> isolates = {};

  // 在dart里list，queue等只有length没有capacity；
  Queue<TaskModel> tasks = Queue.from([]);

  // 先主要用到coreIsolateSize和tasks
  // 创建Executor后必须await先执行init；
  Executor._(this.coreIsolateSize);

  /// 初始化线程池【接下来的优化方向是看init是否用一个单独的master isolate来处理，然后main里的execute都往master isolate发消息】
  static FutureOr<Executor> createExecutor(int coreSize) async {
    var executor = Executor._(coreSize);
    executor.receivePort = ReceivePort();
    executor.receivePort.listen(executor.isolateMessageProcessor);
    // 一次性先创建coreSize个核心线程
    for (var i = 0; i < executor.coreIsolateSize; i++) {
      var debugName = executor._isolateDebugName;
      executor.isolates[debugName] = ExecutorIsolateModel();
      var isolate = await Isolate.spawn(isolateHandler, executor.receivePort.sendPort,
          debugName: debugName);
      executor.isolates[debugName]!.isolate = isolate;
    }
    return executor;
  }

  void isolateMessageProcessor(dynamic message) {
    if (message is IsolateSendPort) {
      // 这个isolate里是发了IsolateSendPort表示肯定是没有task执行了【可以考虑这个free由参数里提供】
      isolates[message.debugName]!.free = true;
      if (tasks.isNotEmpty && isolates[message.debugName]!.free) {
        message.sendPort.send([tasks.removeFirst()]);
        isolates[message.debugName]!.free = false;
        return;
      }
      // 不可能为空
      isolates[message.debugName]!.sendPort = message.sendPort;
      // 所有元素已集齐，inited
      isolates[message.debugName]!.enabled = true;
    } else {
      throw ArgumentError('can not send this type message from sub isolate.');
    }
  }

  // 先只能runnable，且不返还Future
  void execute(Runnable task) {
    var tmp =
        isolates.values.where((isolate) => isolate.enabled && isolate.free);
    if (tmp.isEmpty) {
      tasks.addLast(TaskModel(task));
    } else {
      var freeIsolate = tmp.first;
      freeIsolate.sendPort!.send([TaskModel(task)]);
      freeIsolate.free = false;
      // 由于一次性只发一条消息，然后子isolate的receivePort就作废了（其对应的sendPort也作废），因此这里直接设置为null和不可用【当然此时子isolate是在运作的】
      freeIsolate.sendPort = null;
      freeIsolate.enabled = false;
    }
  }
}

/// 用于executor记录isolate的情况
class ExecutorIsolateModel {
  bool enabled = false;

  late Isolate isolate;

  /// 网Isolate发送业务消息【由于用了receivePort.first后就不能listen了，因此这个放到callback里赋值
  SendPort? sendPort;

  /// 是否空闲
  bool free = true;
}

class IsolateSendPort {
  String debugName;
  SendPort sendPort;

  IsolateSendPort(this.debugName, this.sendPort);
}

/// Function作为消息必须用类包一下
class TaskModel {
  dynamic task;

  TaskModel(this.task);
}

void isolateHandler(SendPort sendPort) async {
  var tasks = Queue<TaskModel>.from([]);
  var currentDebugName = Isolate.current.debugName as String;
  while (true) {
    if (tasks.isNotEmpty) {
      // execute
      var taskModel = tasks.removeFirst();
      taskModel.task();
    } else {
      // receivePort无法重复使用，所以只能消费一条消息后break废弃掉
      var receivePort = ReceivePort(currentDebugName);
      sendPort.send(IsolateSendPort(currentDebugName, receivePort.sendPort));
      await for (var listMsg in receivePort) {
        assert(listMsg is List<TaskModel>);
        tasks.addAll(listMsg);
        break;
      }
    }
  }
}
