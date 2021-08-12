library executor;

import 'dart:async';

import 'package:concurrent_executor/src/basic_component.dart';
import 'package:concurrent_executor/src/executor.dart';

class ExecutorMaster extends Executor {

  /// Prevent users from creating manually
  ExecutorMaster.noManually_(int coreWorkerSize/*ignored*/);

  @override
  Future<void> init() async {
    
  }

  @override
  FutureOr<void> shutdown() {
    // TODO: implement shutdown
    throw UnimplementedError();
  }

  @override
  Future<R> submit<R>(Callable<FutureOr<R>> task) {
      // TODO: implement submit
      throw UnimplementedError();
    }
  
    @override
    Future<R> submitWithState<S, R>(CallableWithState<S, FutureOr<R>> task, S state) {
    // TODO: implement submitWithState
    throw UnimplementedError();
  }
}