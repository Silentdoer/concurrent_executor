var _isolateNumSeed = 1;

/// unique num in single isolate
int isolateIncrementNum() {
  return _isolateNumSeed++;
}

/// unique num in multi isolates
int isolateSharedIncrementNum() {
  throw UnimplementedError();
}
