import 'dart:collection';
import 'dart:io';

import 'dart:isolate';

void main(List<String> args) {
  var executor = Executor(2);
  executor.init();
  // 居然不能用闭包。。【可能闭包无法传输给另一个isolate】
  // 因为闭包的生命周期不是static的；
  /* executor.execute(() {
    print('${Isolate.current.debugName}-aaa');
  }); */

  executor.execute(fuck);

  executor.execute(fuck);

  executor.execute(fuck);

  //sleep(Duration(seconds: 2));
}

void fuck() {
  print('${Isolate.current.debugName}-aaa');
  sleep(Duration(seconds: 1));
}

typedef Runnable = void Function();

class Executor {
  late ReceivePort receivePort;

  /// 线程池里核心线程数
  int coreIsolateSize = 1;

  /// 用于生成每个isolate的debugName
  int _isolateDebugNameIndex = 1;

  String get _isolateDebugName => 'isolate_${_isolateDebugNameIndex++}';

  Map<String, ExecutorIsolateModel> isolates = {};

  // 在dart里list，queue等只有length没有capacity；
  Queue<TaskModel> tasks = Queue.from([]);

  // 先主要用到coreIsolateSize和tasks
  // 创建Executor后必须await先执行init；
  Executor(this.coreIsolateSize);

  /// 初始化线程池
  void init() async {
    receivePort = ReceivePort();
    // TODO 放到其他线程里似乎没有任何意义，因为放到另一个线程，那么里面的tasks等就和main的是两个对象了，因此executor.xx都是没有意义的；
    // 除非是init的那个isolate master的所有变动都发送到main上面的executor对象里；而main上面的executor.execute(..)也是需要发送到init master isolate里的
    // execute产生的task是在main，而isolateMessageProcessor是在master上的，因此execute内部其实又需要发送消息给master

    // 现在也还可以，因为isolate里执行完毕了逻辑处理后才发消息给main，只不过main需要等一下才能接收到消息，至少来说耗时操作是在isolate执行的；
    // 因此要保证main上没有耗时操作，好main接收消息会比较迅速，否则main就必须等这个耗时操作完毕main才能接收isolate的消息
    receivePort.listen(isolateMessageProcessor);
    // 一次性先创建coreSize个核心线程
    for (var i = 0; i < coreIsolateSize; i++) {
      var debugName = _isolateDebugName;
      isolates[debugName] = ExecutorIsolateModel();
      var isolate = await Isolate.spawn(isolateHandler, receivePort.sendPort,
          debugName: debugName);
      // 注意，此时IsolateModel信息不全
      // 这里其实需要同时初始化isolate发给executor的SendPort的用于executor给isolate发消息
      //，但是await receivePort.first后就不能listen了，找了很多资料都不行，所以只好异步完善IsolateModel信息了
      isolates[debugName]!.isolate = isolate;

      /**
       * 所以应该要这样，executor初始化完毕后【isolate都启动了】【可以把每个isolate看成是一个socket服务或者是web 服务】
       * isolate启动后会监听自己的local变量的queue，发现没有数据就会发送一个消息给executor，executor收到消息后就会将task发送给该isolate
       * ，并且将task标记为已经分配（或直接从executor里删除）；
       * 而新增的task都是先放到executor的总的tasks里标记为未分配的；
       * 如果executor收到了isolate的申请task的请求，但是没有多余的task给它则将这个isolate标记为空闲；
       * 一旦来了task，则会从isolate标记属性里获取空闲的分配给它们；
       */
    }
  }

  void isolateMessageProcessor(dynamic message) {
    print('RRR ${Isolate.current.debugName}');
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
      isolates[message.debugName]!.inited = true;
    } else if (message is IsolateMessage) {
      // 这里由于一次性只能发一条消息，所以要inited重新弄为false
      // TODO 貌似不需要了？
      print('收到了来自${message.debugName}的${message.type}消息');
    } else {
      throw ArgumentError('can not send this type message from sub isolate.');
    }
  }

  // 先只能runnable，且不返还Future
  void execute(Runnable task) {
    var tmp =
        isolates.values.where((isolate) => isolate.inited && isolate.free);
    if (tmp.isEmpty) {
      // 当然，这里可以看要不要优化，即所有的isolate都在工作，但是也是可以send task给它的，省的它没哟task来发消息让executor给它task
      tasks.addLast(TaskModel(task));
    } else {
      var freeIsolate = tmp.first;
      // TODO 这里先不考虑send发送失败之类的
      // execute 里只给一个，但是如果收到了isolate的空了的请求可以看tasks数量多少来决定给多少个
      freeIsolate.sendPort!.send([TaskModel(task)]);
      freeIsolate.free = false;
      // TODO 由于ReceivePort的限制，导致我这里只能把ReceivePort当成一次性筷子，对应的SendPort也就没用了，所以这里还需做这两个操作
      {
        freeIsolate.sendPort = null;
        freeIsolate.inited = false;
      }
    }
  }
}

class TaskModel {
  /// Runnable or Callable<R>
  dynamic task;

  /// 这个似乎也没有用到，因为assigned的都已经从tasks里去掉了
  //bool assigned = false;

  /// 先不搞这么复杂
  //String? assignedIsolateDebugName;

  TaskModel(this.task);
}

/// 用于executor记录isolate的情况
class ExecutorIsolateModel {
  bool inited = false;

  late Isolate isolate;

  /// 从Isolate里获取业务消息【其实如果多个isolate对象是公用一个的，这个直接定义在Executor里即可，都不需要在这个类里定义】
  //ReceivePort receivePort;

  /// 网Isolate发送业务消息【由于用了receivePort.first后就不能listen了，因此这个放到callback里赋值
  SendPort? sendPort;

  /// 是否空闲
  bool free = true;

  //ExecutorIsolateModel(this.receivePort);
}

class ExecutorMessage {
  /// 这里有问题，由于非SendPort的消息都是深拷贝的（哪怕是一个函数对象），因此这里怎么让executor的map进行比较呢？
  /// 所以message又得单独实现一个类型，然后重载里面的==和equals
  /// 我们传的是Function，所以不需要【哪怕是对象，如果对象里有字段是Function的task，也可以通过这个来判断】
  Runnable task;

  ExecutorMessage(this.task);
}

class IsolateSendPort {
  String debugName;
  SendPort sendPort;

  IsolateSendPort(this.debugName, this.sendPort);
}

/// Isolate 给executor发送的消息的格式【目前isolate给executor发的消息，一种是IsolateSendPort，一种就是这个】
class IsolateMessage {
  /// 发消息的isolate的debugName
  String debugName;

  /// 发送消息的类型，比如是请求消费message还是新增message（message是task）还是啥的
  IsolateMessageTypeEnum type;

  IsolateMessage(this.debugName, this.type);
}

enum IsolateMessageTypeEnum {
  addRequest,
}

void isolateHandler(SendPort sendPort) async {
  var tasks = Queue<TaskModel>.from([]);
  /* var receivePort = ReceivePort(Isolate.current.debugName!);
    // first send sendPort to executor
    sendPort.send(
        IsolateSendPort(Isolate.current.debugName!, receivePort.sendPort)); */

  //region two ways
  /// 似乎直接await for receivePort就行了，干嘛要外面再加一层while
  /// 好吧，我知道为什么需要再加一层了，因为这里没有了数据需要告诉外部我没有tasks了快给我一些
  /* await for (var msg in receivePort) {
      // 这里还可以对msg的类型进行区分，但是似乎没有必要，executor只会给isolate发TaskModel
      if (msg is TaskModel) {
        // 执行完毕自动从
        msg.task();
      }
    } */

  // 开始不断的获取task来执行【和上面的await for是互相对应的，目前看哪种更可行】
  // ss!是不正确的用法ss!.xx才是正确的，如果是要ss的非nullable可以用ss as Foo来实现（ss是Foo?）
  var currentDebugName = Isolate.current.debugName as String;
  while (true) {
    if (tasks.isNotEmpty) {
      var taskModel = tasks.removeFirst();
      // 执行
      taskModel.task();
    } else {
      //{
      var receivePort = ReceivePort(currentDebugName);
      // first send sendPort to executor
      sendPort.send(IsolateSendPort(currentDebugName, receivePort.sendPort));
      //}
      // 请求executor送一些task来
      // 似乎不需要这个了，没数据了是直接发sendPort出去，然后外部就直接弄task过来；
      /* sendPort.send(
          IsolateMessage(currentDebugName, IsolateMessageTypeEnum.addRequest)); */
      // 规定，这里只发数组，哪怕是一个数据，然后executor一次性给isolate只发一个数据，这样就不会出现漏数据的情况了
      // 否则receivePort new一个新的，万一此时executor又给它发了消息，那么这个消息就没人消费了
      await for (var listMsg in receivePort) {
        assert(listMsg is List<TaskModel>);
        tasks.addAll(listMsg);
        /* receivePort = ReceivePort(Isolate.current.debugName!);
          sendPort.send(IsolateSendPort(
              Isolate.current.debugName!, receivePort.sendPort)); */
        break;
      }
    }
  }
  //endregion
}
