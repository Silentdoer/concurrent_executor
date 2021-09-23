abstract class WorkerMessageState {
  int taskId;

  WorkerMessageState(this.taskId);
}

class SuccessMessageState extends WorkerMessageState {
  var result;

  SuccessMessageState(int taskId, this.result) : super(taskId);
}

class ErrorMessageState extends WorkerMessageState {
  Object error;
  String stackTrace;

  ErrorMessageState(int taskId, this.error, this.stackTrace) : super(taskId);
}

enum MessageType {
  /// worker is idle, request pull tasks from executor
  idle,
  success,
  error,
}

enum CloseLevel {
  immediately,
  afterRunningFinished,
  afterAllFinished,
}

/// message from worker
class WorkerMessage {
  MessageType type;

  String workerDebugName;

  WorkerMessageState? state;

  WorkerMessage(this.type, this.workerDebugName);
}

class CloseMessage {
  CloseLevel level = CloseLevel.afterRunningFinished;
}
