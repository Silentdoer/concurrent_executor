bool isVoidType<T>() {
  var tlist = <T>[];
  var voidList = <void>[];
  if (tlist.runtimeType == voidList.runtimeType) {
    return true;
  } else {
    return false;
  }
}

final voidType = _getType<void>();

Type _getType<T>() => T;
