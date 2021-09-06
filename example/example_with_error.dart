import 'dart:io';
import 'dart:isolate';

import 'package:concurrent_executor/concurrent_executor.dart';
import 'package:concurrent_executor/src/task/concurrent_task.dart';

void main(List<String> args) async {
  var executor = await Executor.createExecutor(3);

  var ts = TaskImpl();
  executor.submit(ts);

  executor.submit(ts);

  executor.submit(ts);

  executor.submit(ts);

  executor.submit(ts);
  await Future.delayed(Duration(seconds: 1));
  ts.sss = 'kkk';
  executor.submit(ts).onError((error, stackTrace) {
    print('main');
    print(error);
    print(stackTrace);
    return Future.value(3);
  });

  //sleep(Duration(seconds: 2));
  var receivePort = ReceivePort();
  await Isolate.spawn(mm, receivePort.sendPort);

  await for (var msg in receivePort) {
    break;
  }
  print('await ok');
  await executor.submit(ts).onError((error, stackTrace) {
    print('main');
    print(error);
    //print(stackTrace);
    return Future.value(3);
  });

  executor.close();
}

void mm(SendPort message) {
  sleep(Duration(seconds: 3));
  print('message');
  message.send(88);
}

class TaskImpl extends ConcurrentTask<int> {
  String sss = '334';

  @override
  int run() {
    print('${Isolate.current.debugName}-aaa-$sss');
    //sleep(Duration(seconds: 1));

    var res = int.parse(sss);
    return res;
  }
}
