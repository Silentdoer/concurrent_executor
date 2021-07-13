import 'dart:async';

import 'dart:collection';

void main(List<String> args) {
  var ss = [TaskWrapper.name(sss, 'sss')];
  //Callable sssb = sss;
  // Function就类似dynamic，只不过是局限于Function类型的dynamic
  Function su = sss;
  su('ooo');
  su = () =>8;
  print(su());
}

int sss(String s) {
  return 0;
}

Queue<TaskWrapper<dynamic, dynamic>> tasks = Queue.from([]);

/* FutureOr<R> submit<S, R>(Callable<S, FutureOr<R>> callable, S state) {
  TaskWrapper taskWrapper;
  // if R is void, so i need not return a future
  if (isVoidType<R>()) {
    // flag1, this will be error,
    //taskWrapper = TaskWrapper.name(callable, state);
    var tmp = TaskWrapper.name(callable, state);
    tmp.isVoidType = true;
    taskWrapper = tmp;
    // to do some other logic..
  } else {
    // need reture future
    var completer = Completer<R>();
    var tmp = TaskWrapper.name(callable, state);
    tmp.isVoidType = false;
  }
} */

typedef Callable<S, R> = R Function(S state);

class TaskWrapper<S, R> {
  Callable<S, R> task;

  S state;

  late bool isVoidType;

  TaskWrapper.name(this.task, this.state);
}

bool isVoidType<T>() {
  var list = <T>[];
  var s = <void>[];
  if (list.runtimeType == s.runtimeType) {
    return true;
  } else {
    return false;
  }
}