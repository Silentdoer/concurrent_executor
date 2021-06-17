import 'dart:io';
import 'dart:isolate';

import 'package:concurrent_executor/concurrent_executor.dart';

void main(List<String> args) async {
  var executor = await Executor.createExecutor(2);

  // 同一个文件里如果直接发送函数是可以的，但是用包的形式就不行了。。
  executor.execute(fuck);

  executor.execute(fuck);

  executor.execute(fuck);

  executor.execute(fuck);

  executor.execute(fuck);

  executor.execute(fuck);

  //sleep(Duration(seconds: 2));
  var receivePort = ReceivePort();
  await Isolate.spawn(mm, receivePort.sendPort);

  await for (var msg in receivePort) {
    break;
  }
  print('await ok');
  executor.execute(fuck);
}

void mm(SendPort message) {
  sleep(Duration(seconds: 3));
  print('message');
  message.send(88);
}

void fuck() {
  print('${Isolate.current.debugName}-aaa');
  sleep(Duration(seconds: 1));
}
