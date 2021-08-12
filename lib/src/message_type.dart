enum _MessageType {
  // 告诉master自己task空了
  empty,
  // 请求拉取task，可能还没有空，但是快空了
  pull,
  complete,
  shutdown,
  push,
}