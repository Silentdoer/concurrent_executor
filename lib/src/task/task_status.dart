enum TaskStatus {
  idle,

  /// sent to worker, can not cancel
  ready,
  //executing,
  success,
  error,
}
