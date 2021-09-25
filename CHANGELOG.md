## 0.1.0

- Initial version. empty tasks receiver isolate is main(or other invoker isolate)


## 0.2.0

- Modify the method of creating executors to optimize message communication between isolates

## 0.3.0

- Optimized Executor can return FutureOr<R> after submitting the task. If R is void, it will directly return null. If the response value of the task is Future, the Future will be returned to the user after execution in the worker.

## 0.4.0

- support task state

## 0.5.0

- allow state with a custom type.

## 0.5.1

- fix wrapper declare

## 0.7.0

- update english comment, finished executor close method.

## 0.7.1

- support fetch executor unfinished tasks.
- fix afterRunningFinished

## 0.7.2

- fix multi ilde message from worker in initial status

## 0.8.0

- refactor unfinishedTasks method
- update README example

## 0.9.0

- update minimum sdk support.

## 0.9.1

- fix meta