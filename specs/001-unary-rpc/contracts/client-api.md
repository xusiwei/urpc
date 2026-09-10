# Contract: Client API（C++ 公共接口）

目标层：`libs/api`（`#include <urpc/client.h>` 等）。接口契约，非最终
头文件排版；错误均以 `Status` 表达，无异常穿越 API 边界。

## 通道与调用

```cpp
// 创建通道（线程安全；内部专属事件循环线程）
ChannelOptions opts;
opts.set_max_receive_message_size(4 * 1024 * 1024);   // 默认 4MiB
std::shared_ptr<Channel> channel = Channel::Connect("127.0.0.1:50051", opts);
// 失败：懒连接语义——首个调用返回 UNAVAILABLE，不抛异常

// 异步调用（主形态，任意线程可用；代理/通道对象线程安全，FR-005）
auto handle = stub.CallAsync(
    request,                                        // upb 强类型请求
    /*deadline=*/std::chrono::milliseconds(3000),   // 可选；默认不超时
    [](Result<EchoResponse> result) {               // 恰好回调一次
      if (result.ok()) { /* result.Value() */ }
      else           { /* result.Status() */ }
    });
handle.Cancel();   // 可选：主动取消（服务端将收到取消通知）

// 同步便捷形态（仅限框架事件循环线程之外；误用立即返回明确错误）
Result<EchoResponse> result = stub.Call(request, std::chrono::milliseconds(3000));
```

## Result / Status 形态

```cpp
enum class StatusCode {
  kOk, kUnimplemented, kInternal, kDeadlineExceeded,
  kResourceExhausted, kUnavailable, kDataLoss,
};  // FR-003 集合（本特性闭合）

Status{StatusCode code, std::string message};      // C++17 聚合
Result<T>{Status, std::optional<T>};               // ok() ⇔ code == kOk
```

## 契约要点

| 契约 | 对应 |
|------|------|
| 回调恰好一次；终态后 Handle 只读 | data-model Call 终态一次 |
| 同一 stub/通道多线程并发调用；单连接 HTTP/2 多路流承载 | FR-005 / Clarifications #4 |
| 同步接口在框架事件循环线程内调用 → 立即返回明确错误（快速失败） | FR-002 / Clarifications #5 |
| deadline 随调用传播（grpc-timeout）；超时 → DEADLINE_EXCEEDED 且服务端收取消通知 | FR-004 |
| 目标不可达/通道断开 → UNAVAILABLE（不无限等待） | spec 边界情形 |
| 未知方法 → UNIMPLEMENTED；消息超限 → RESOURCE_EXHAUSTED | FR-006/FR-007 |
