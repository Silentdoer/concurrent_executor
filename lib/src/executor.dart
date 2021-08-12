library executor;

import 'dart:async';

import 'package:meta/meta.dart';

import 'package:concurrent_executor/src/basic_component.dart';
import 'package:concurrent_executor/src/executor_web/executor_master_web.dart'
  if (dart.library.io) 'package:concurrent_executor/src/executor_io/executor_master_io.dart';

abstract class Executor {

  @protected
  Future<void> init();

  /// need user shutdown executor manually
  FutureOr<void> shutdown();

  /// 初始化线程池【接下来的优化方向是看init是否用一个单独的master isolate来处理，然后main里的execute都往master isolate发消息】
  static Future<Executor> createExecutor([int coreWorkerSize = 1]) async {
    var executor = ExecutorMaster.noManually_(coreWorkerSize);
    await executor.init();
    return executor;
  }

  /// 之前设计有问题，不管返回类型是否是void，都应该返回一个Future对象
  /// 因为Future对象可以添加完成后执行什么之类的逻辑，即future.then(...)
  /// 并不是说返回值是void的task就不需要await，只是不需要它的返回值，但是可能依赖它完成后
  /// 需要同步执行什么操作。
  Future<R> submit<R>(Callable<FutureOr<R>> task);

  /// FutureOr<R>是union类型，它既是R也可以是Future<R>类型
  /// fuck，似乎很难做到state自定义类型。。
  Future<R> submitWithState<S, R>(CallableWithState<S, FutureOr<R>> task, S state);
}