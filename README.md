A concurrent executor library for Dart developers.

## Usage

A simple usage example:

```dart
import 'dart:io';
import 'dart:isolate';

import 'package:concurrent_executor/concurrent_executor.dart';

void main() async {
  var executor = await Executor.createExecutor(2);

  executor.submit(foo);

  executor.submit(foo);

  executor.submit(foo);
}

void foo() {
  print('${Isolate.current.debugName}-aaa');
  sleep(Duration(seconds: 1));
}
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/Silentdoer/concurrent_executor/issues
