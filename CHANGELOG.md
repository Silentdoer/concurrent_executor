## 0.1.0

- Initial version. empty tasks receiver isolate is main(or other invoker isolate)


## 0.2.0

- 修改创建executor的方式，优化isolate之间消息通讯

## 0.3.0

- 优化Executor可以submit task后返回FutureOr<R>，如果R是void类型则直接返回null，如果task的响应值是Future，则Future会在worker里执行完毕后返回给用户

## 0.4.0

- support task state