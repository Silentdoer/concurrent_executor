abstract class WorkerMessageState {
  int taskId;

  WorkerMessageState(this.taskId);
}

class CompleteMessageState extends WorkerMessageState {
  var result;

  CompleteMessageState(int taskId, this.result) : super(taskId);
}

class ErrorMessageState extends WorkerMessageState {
  Object error;
  String stackTrace;

  ErrorMessageState(int taskId, this.error, this.stackTrace) : super(taskId);
}

enum MessageType {
  idle,
  pull,
  success,
  error,
}

class WorkerMessage {
  MessageType type;

  String workerDebugName;

  WorkerMessageState? state;

  WorkerMessage(this.type, this.workerDebugName);
}
