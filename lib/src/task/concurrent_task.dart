import 'dart:async';

import 'package:concurrent_executor/src/task/task_status.dart';

/// all task should implements this
abstract class ConcurrentTask<R> {
  R run();
}

class TaskWrapperBase<R> {
  ConcurrentTask<R> task;

  int taskId;

  TaskWrapperBase(this.task, this.taskId);
}

class TaskWrapper<R> extends TaskWrapperBase<R> {
  static int _taskIdSeed = 1;

  TaskStatus status = TaskStatus.created;

  Completer<R> completer;

  TaskWrapper(ConcurrentTask<R> task, this.completer)
      : super(task, _taskIdSeed++);

  TaskWrapperBase<R> toSend() {
    return TaskWrapperBase(task, taskId);
  }
}
