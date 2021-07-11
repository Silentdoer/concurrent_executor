import 'dart:async';

import 'dart:collection';

import 'dart:isolate';

void main(List<String> args) async {
  var completer = Completer();
  completer.future;
  completer.complete(8);
  int s = 9223372036854775807;
  print(s.isFinite);
  print(s);
  s++;
  print(s.isFinite);
  print(s);
  //ss<void>();

  Queue<int> que = Queue.from([1, 2, 3]);
  // first是只要没有remove掉，那么first永远是第一个元素
  print(que.first);
  print(que.first);
  print(que.removeFirst());
  print(que.first);

  //ss<int>(uu);

  ses<int>(uu);
  ses(uu);
  ses(kk);

  Uk.mm++;
  print(Uk.mm++);
  print(Uk.mm++);

  var recei = ReceivePort();
  var bstream = recei.asBroadcastStream();
  await Isolate.spawn(handler, recei.sendPort);
  late SendPort sendPort;
  await for (var msg in bstream) {
    if (msg is SendPort) {
      sendPort = msg;
      break;
    }
  }
  print('start listen');
  bstream.listen(listenMet);
  sendPort.send(uu);
  print(await kks());
  print('end');
}

Completer<int>? completer;

Future<int> kks() {
  completer = Completer<int>();
  return completer!.future;
}

void listenMet(var msg) {
  completer!.complete(msg);
}

void handler(SendPort sendPort) async {
  ReceivePort rec = ReceivePort();

  sendPort.send(rec.sendPort);
  var stream = rec.asBroadcastStream();
  await for (var msg in stream) {
    var result = msg();
    sendPort.send(899);
  }
}

typedef Callable<R> = R Function();

class TaskWrapper<R> {
  Callable<R> task;
  Completer? completer;

  TaskWrapper(this.task);
}

void kk() {}

int uu() {
  print('基斯里夫看见了');
  return 9;
}

/* FutureOr<R> ss<R>() {
  return null;
} */

void ss<R>(R Function() f) {
  if (f is void Function()) {
    print('ok11111');
  }
}

typedef F = void Function();

void ses<R>(R Function() f) {
  print(f.runtimeType);
  if (R == int) {
    print('ok11111');
  }
  //void Function() F;
  if (f.runtimeType == F) {
    print('EEEEEEE${f.runtimeType}');
  }
  F s = uu;
}

/*
void ss<R>(Callable<R> task){}
*/
class Uk<R> {
  static int mm = 1;
}
