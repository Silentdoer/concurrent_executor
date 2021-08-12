import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:concurrent_executor/src/basic_component.dart';

class WorkerWrapper {
  /// such as worker not initialized, or already closed
  bool available = false;

  /// whether the worker is currently idle
  bool idle = true;

  late Isolate _isolate;

  final String _debugName;

  /// The master isolate sends message to the worker through this sendPort
  /// TODO can private with offer method
  late SendPort sendPort;

  WorkerWrapper(this._debugName);

  FutureOr<void> init(SendPort masterSendPort, Stream bstream) async {
    _isolate = await Isolate.spawn(_workerHandler, masterSendPort,
        debugName: _debugName);
    await for (var msg in bstream) {
      if (msg is SendPort) {
        sendPort = msg;
        available = true;
        break;
      }
    }
  }

  static void _workerHandler(SendPort masterSendPort) async {
    //print('###${Isolate.current.debugName}');
    var tasks = Queue<dynamic>.from([]);
    var currentDebugName = Isolate.current.debugName as String;
    var receivePort = ReceivePort(currentDebugName);
    // 往master isolate里发送用于和worker通信的sendPort
    masterSendPort.send(receivePort.sendPort);
    var bstream = receivePort.asBroadcastStream();
    while (true) {
      if (tasks.isNotEmpty) {
        // execute【在一个文件里是可以直接发送函数的，但是用了包不知道为什么就不行了】
        var taskWrapper = tasks.removeFirst();
        /* if (taskWrapper.isReturnVoid) {
          if (taskWrapper is TaskWithStateWrapper) {
            taskWrapper.task(taskWrapper.state);
          } else {
            taskWrapper.task();
          }
          continue;
        } */
        dynamic result;
        if (taskWrapper is TaskWithStateWrapper) {
          // 还是报这个错误，所以我这里要考虑到一点，就是一个task发送到其他地方去执行的时候
          // 已经不会存它的类型了，因此只能以dynamic的方式去执行，，，，很蛋疼啊；
          // 所以存的时候就应该将task存为dynamic的类型，fuck
          //result = Function.apply(taskWrapper.task, taskWrapper.state);
          // 用这个会报：type '(String) => int' is not a subtype of type '(dynamic) => dynamic'
          //print('bbbb');
          // 这里是taskWrapper.task的时候就已经报错了，因为taskWrapper是dynamic和dynamic，所以这里
          // 将task进行了强制转换为了(dynamic) => dynamic而报错的。
          // TODO 所以taskWrapper的泛型不应该和Callable的泛型对应起来；
          //print(taskWrapper.task.runtimeType);
          //print(taskWrapper.state.runtimeType);
          // 没有必要再判断是不是void返回类型
            result = taskWrapper.task(taskWrapper.state);
          
        } else {
          
            result = taskWrapper.task();
        }
        // 在这里Future是Class类型[Future对象可以作为消息发送吗？（不要，否则一直await）]
        // 在哪个isolate产生的Future对象就要在哪个isolate里await而不能send给其他isolate await
        while(result is Future) {
          // 防止Future<Future<Future...套娃
          
            result = await result;
         
        }
        

        // 执行完毕要给master发消息，让master对此task进行complete【在isolate里complete不会在master里生效】
        masterSendPort.send(Message(MessageType.complete, currentDebugName)
          ..state = CompleteMessageState(taskWrapper.taskId!, result));
      } else {
        // tasks里没有task任务了，请求isolate master分配一些，告诉master是哪个worker要task【甚至还可以支持要多少。。】
        masterSendPort.send(Message(MessageType.empty, currentDebugName));
        await for (var listMsg in bstream) {
          tasks.addAll(listMsg);
          break;
        }
      }
    }
  }

  FutureOr<bool> shutdown() {
    _isolate.kill();
    return true;
  }
}
