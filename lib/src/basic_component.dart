import 'dart:async';

typedef Callable<R> = R Function();

typedef CallableWithState<S, R> = R Function(S);

var _taskIdSeed = 1;

class TaskWrapper<R> {
  Callable<FutureOr<R>> task;

  Completer<R>? completer;

  int? taskId;

  /// 是否已经处于就绪状态【即已经发给了worker将执行】
  bool ready = false;

  bool isReturnVoid = false;

  /// 这里taskId不能用task的hashCode，因为多个task的方法对象可能是同一个，因此会重复
  TaskWrapper(this.task, this.completer) : taskId = _taskIdSeed++;

  TaskWrapper.nonCompleter(this.task, this.taskId, this.isReturnVoid);

  TaskWrapper.justTask(this.task);
}

/// 因为要判断是否是_TaskWithStateWrapper，这种情况下虽然task有S和R的类型，但是没法取出来
/// 所以这里只能是把task当成CallableWithState<dynamic, dynamic>来取出来，因此保存的时候就不该用
/// 到泛型来保存【数据除外，数据的dynamic可以和其他类型直接转换，但是function不一样，会报：
/// type '(String) => int' is not a subtype of type '(dynamic) => dynamic'
class TaskWithStateWrapper<S, R> {
  // 这里不能存S，否则报上面的错误
  // Function 是所有Function对象的超级（类似是dynamic一样）
  Function task;

  S state;

  Completer<R>? completer;

  int? taskId;

  /// 是否已经处于就绪状态【即已经发给了worker将执行】
  bool ready = false;

  bool isReturnVoid = false;

  /// 这里taskId不能用task的hashCode，因为多个task的方法对象可能是同一个，因此会重复
  TaskWithStateWrapper(this.task, this.state, this.completer) : taskId = _taskIdSeed++;

  TaskWithStateWrapper._nonCompleter(this.task, this.state, this.taskId, this.isReturnVoid);

  TaskWithStateWrapper.justTask(this.task, this.state);

  TaskWithStateWrapper<S, R> toNonCompleter() {
    return TaskWithStateWrapper._nonCompleter(task, state, taskId, isReturnVoid);
  }
}

class CompleteMessageState {
  int taskId;
  var result;

  CompleteMessageState(this.taskId, this.result);
}

enum MessageType {
  // 告诉master自己task空了
  empty,
  // 请求拉取task，可能还没有空，但是快空了
  pull,
  complete,
}

class Message {
  MessageType type;

  String workerDebugName;

  dynamic state;

  Message(this.type, this.workerDebugName);
}