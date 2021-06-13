A concurrent executor library for Dart developers.

## Usage

A simple usage example:

```dart
import 'package:concurrent_executor/concurrent_executor.dart';

void main() {
  var executor = Executor(2);
  executor.init();

  executor.execute(foo);

  executor.execute(foo);

  executor.execute(foo);
}

void foo() {
  print('${Isolate.current.debugName}-aaa');
  sleep(Duration(seconds: 1));
}
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/Silentdoer/concurrent_executor/issues
