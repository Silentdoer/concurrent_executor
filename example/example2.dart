import 'dart:io';
import 'dart:isolate';

import 'package:concurrent_executor/concurrent_executor.dart';

void main() async {
  var executor = await Executor.createExecutor(2);

  executor.submit(foo);

  var res = executor.submit(foo);
  print(res);

  var res222 = executor.submit(foo2);
  print(await res222);

  var res2 = executor.submit(foo2);
  print(res2);

  var res22 = executor.submit(foo2);
  print(await res22);

  var res3 = executor.submit(foo3);
  print(await res3);

  var res33 = executor.submit(foo3);
  print(res33);

  var res333 = executor.submit(foo3);
  print(await res333);

  var res44 = executor.submitWithState(foo4, '时代峰峻了');
  print(res44);

  var res444 = executor.submitWithState(foo4, '司法局');
  print(await res444);

  var res5 = executor.submitWithState(foo5, 99);
  print(await res5);

  var res6 = executor.submitWithState(foo6, '发动机可怜');
  print(await res6);

  // region pause
  var receivePort = ReceivePort();
  await Isolate.spawn(pause, receivePort.sendPort);
  await for (var _ in receivePort) {
    break;
  }
  // endregion

  executor.shutdown();
}

void foo() {
  print('${Isolate.current.debugName}-aaa');
  sleep(Duration(seconds: 1));
}

int foo2() {
  print('${Isolate.current.debugName}-aaa');
  sleep(Duration(seconds: 1));
  return 3;
}

Future<int> foo3() async {
  return await Future.value(9);
}

int foo4(Object? stat) {
  print('${Isolate.current.debugName}-aaa-${stat}');
  sleep(Duration(seconds: 1));
  return 344;
}

int foo5(int stat) {
  print('${Isolate.current.debugName}-aaa-${stat}');
  sleep(Duration(seconds: 1));
  return stat;
}

int foo6(String stat) {
  print('${Isolate.current.debugName}-aaa-${stat}');
  sleep(Duration(seconds: 1));
  return 6663;
}

void pause(SendPort message) {
  sleep(Duration(seconds: 3));
  message.send('close');
}
