# Contract: Server API（C++ 公共接口）

目标层：`libs/api`（`#include <urpc/server.h>` 等）。以下为接口契约，
非最终头文件排版；错误均以 `Status` 表达，无异常穿越 API 边界。

## 构建/运行

```cpp
// 构建、启动、关闭
ServerBuilder builder;
builder.set_listen_address("127.0.0.1:50051");     // 必填
builder.set_max_receive_message_size(4 * 1024 * 1024);  // 默认 4MiB
builder.set_shutdown_grace(std::chrono::seconds(10));   // 默认 10s

std::shared_ptr<Server> server = builder.BuildAndStart();
// 运行直至 Shutdown；BuildAndStart 失败返回 nullptr + GetLastError

server->Shutdown();            // 优雅排空（FR-012）：GOAWAY → 等待/宽限 → 强制
server->Wait();                // 阻塞至 STOPPED（仅非循环线程可用）
```

## 注册一元方法

```cpp
// Handler 完成回调：一次性写出结果
server->RegisterUnary(
    "example.EchoService", "Echo",
    [](ServerContext& ctx, const EchoRequest& req,
       UnaryHandlerDone done) {
      // ctx: 截止时间视图 + 取消感知（见下）
      EchoResponse resp;      // upb 强类型消息
      resp.set_text(req.text());
      done(Status::Ok(), resp);          // 成功
      // 或 done(Status(StatusCode::kInternal, "reason"), std::nullopt)
    });
// 返回 Status：重复路径注册返回错误（不静默覆盖）
// 运行期可调用（动态注册，US1-2）
```

## ServerContext（处理器视角）

```cpp
class ServerContext {
 public:
  // 是否已达截止时间（轮询视图）
  bool IsCancelled() const;
  // 注册取消回调（触发：截止时间到 / 客户端取消 / 优雅关闭强制阶段）
  void OnCancel(std::function<void()> cb);
  // 剩余时间视图（供业务自定义超时判断）
  std::chrono::milliseconds TimeRemaining() const;
};
// 取消后处理器不得再 done() 写响应；迟到的 done 以错误返回，不崩溃
```

## 契约要点

| 契约 | 对应 |
|------|------|
| 处理器回调在框架事件循环线程执行；长任务应自行投递并异步 done | research.md §4 |
| done() 恰好调用一次（成功或失败二选一） | data-model Call 终态一次 |
| 取消通知先于客户端超时结果收尾发出 | FR-004 / Clarifications #1 |
| 未知路径 → UNIMPLEMENTED；处理器内错误 → INTERNAL | FR-006 |
| 解码失败 → DATA_LOSS，连接保持 | spec 边界情形 |
