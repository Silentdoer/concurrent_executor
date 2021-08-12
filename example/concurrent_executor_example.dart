import 'dart:io';
import 'dart:isolate';

import 'package:concurrent_executor/concurrent_executor.dart';
import 'package:pedantic/pedantic.dart';

void main() async {
  var executor = await Executor.createExecutor(2);

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

  var res2 = executor.submit(foo2);
  print(res2);

  var res22 = executor.submit(foo2);
  print(await res22);

  var foo3 = Foo3();
  var res3 = executor.submit(foo3);
  print(await res3);

  var res33 = executor.submit(foo3);
  print(res33);

  var res333 = executor.submit(foo3);
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
  print(await res6);

  // region pause
  var receivePort = ReceivePort();
  await Isolate.spawn(pause, receivePort.sendPort);
  await for (var _ in receivePort) {
    break;
  }
  // endregion

  executor.close();
}

class Foo extends ConcurrentTask<void> {
  @override
  void run() {
    print('${Isolate.current.debugName}-aaa');
    sleep(Duration(seconds: 1));
  }
}

class Foo2 extends ConcurrentTask<int> {
  @override
  int run() {
    print('${Isolate.current.debugName}-aaa');
    sleep(Duration(seconds: 1));
    return 3;
  }
}

class Foo3 extends ConcurrentTask<Future<int>> {
  @override
  Future<int> run() async {
    return await Future.value(9);
  }
}

class Foo4 extends ConcurrentTask<int> {
  Object? stat = 888;

  @override
  int run() {
    print('${Isolate.current.debugName}-aaa-$stat');
    sleep(Duration(seconds: 1));
    return 344;
  }
}

class Foo5 extends ConcurrentTask<int> {
  var stat = 85288;

  @override
  int run() {
    print('${Isolate.current.debugName}-aaa-$stat');
    sleep(Duration(seconds: 1));
    return stat;
  }
}

class Foo6 extends ConcurrentTask<int> {
  String stat = '';

  @override
  int run() {
    print('${Isolate.current.debugName}-aaa-$stat');
    sleep(Duration(seconds: 1));
    return 6663;
  }
}

void pause(SendPort message) {
  sleep(Duration(seconds: 3));
  message.send('close');
}
