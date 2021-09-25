import 'dart:io';
import 'dart:isolate';

import 'package:concurrent_executor/concurrent_executor.dart';
import 'package:pedantic/pedantic.dart';

void main() async {
  var executor = await Executor.createExecutor(3);

  var foo = Foo();
  unawaited(executor.submit(foo).then((value) => value, onError: (e, s) {
    print(e);
    print(s);
  }));

  var res = executor.submit(foo);
  print(res);

  var foo2 = Foo2();
  var res222 = executor.submit(foo2);
  print(await res222);

  var res22 = executor.submit(foo2);
  print(await res22);

  var foo3 = Foo3();
  var res3 = executor.submit(foo3);
  print(res3);

  var res33 = executor.submit(foo3);
  print(res33);

  var foo33 = Foo3();
  var res333 = executor.submit(foo33);
  print(await res333);

  var foo4 = Foo4();
  foo4.stat = 'aaaaccc';
  var res44 = executor.submit(foo4);
  print(res44);

  var foo44 = Foo4();
  foo44.stat = 'vvvveee';
  var res444 = executor.submit(foo44);
  print(await res444);

  var foo5 = Foo5();
  foo5.stat = 99;
  var res5 = executor.submit(foo5);
  print(await res5);

  var foo6 = Foo6();
  foo6.stat = 'kkkkttt';
  var res6 = executor.submit(foo6);
  print(res6);

  // region pause
  var receivePort = ReceivePort();
  await Isolate.spawn(pause, receivePort.sendPort);
  await for (var _ in receivePort) {
    break;
  }
  print('pause close');
  receivePort.close();
  // endregion

  //await executor.close(CloseLevel.immediately);
  //executor.close(CloseLevel.immediately);
  //await executor.close(CloseLevel.afterRunningFinished);
  // close default is afterRunningFinished
  await executor.close();
  //await executor.close(CloseLevel.afterAllFinished);
  //executor.close(CloseLevel.afterAllFinished);
  print(
      'the following ${executor.unfinishedTasks.length} tasks has not executed completely:');
  print(executor.unfinishedTasks.map((e) => e.runtimeType));
}

class Foo extends ConcurrentTask<void> {
  @override
  void run() {
    print('${Isolate.current.debugName}-executeFoo');
    sleep(Duration(seconds: 1));
  }
}

class Foo2 extends ConcurrentTask<int> {
  @override
  int run() {
    print('${Isolate.current.debugName}-executeFoo2');
    sleep(Duration(seconds: 1));
    return 3;
  }
}

class Foo3 extends ConcurrentTask<Future<int>> {
  @override
  Future<int> run() async {
    print('${Isolate.current.debugName}-executeFoo3');
    return await Future.value(9);
  }
}

class Foo4 extends ConcurrentTask<int> {
  Object? stat = 888;

  @override
  int run() {
    print('${Isolate.current.debugName}-executeFoo4-$stat');
    sleep(Duration(seconds: 1));
    return 344;
  }
}

class Foo5 extends ConcurrentTask<int> {
  var stat = 85288;

  @override
  int run() {
    print('${Isolate.current.debugName}-executeFoo5-$stat');
    sleep(Duration(seconds: 1));
    return stat;
  }
}

class Foo6 extends ConcurrentTask<int> {
  String stat = '';

  @override
  int run() {
    print('${Isolate.current.debugName}-executeFoo6-$stat');
    sleep(Duration(seconds: 1));
    return 6663;
  }
}

void pause(SendPort message) {
  sleep(Duration(seconds: 1));
  message.send('close');
}
