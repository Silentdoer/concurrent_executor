import 'dart:isolate';

void main(List<String> args) async {
  var receivePort = ReceivePort();
  await Isolate.spawn(handler, receivePort.sendPort);
  var bstream = receivePort.asBroadcastStream();
  late SendPort sendPort;
  await for (var msg in bstream) {
    sendPort = msg;
    break;
  }
  sendPort.send('ssss');
  sendPort.send('ssss222');
  receivePort.close();
}

void handler(SendPort sendPort) {
  var receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    print(message);
  });
}
