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

void pause(SendPort message) {
  sleep(Duration(seconds: 3));
  message.send('close');
}
